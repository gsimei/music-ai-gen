import test from "node:test"
import assert from "node:assert/strict"
import { File } from "node:buffer"
import { readFileSync } from "node:fs"
import { draftFields, restoreDraftFields, claimDraft, saveMedia, loadMedia } from "../../app/javascript/campaign_media_store.js"

// Replace only Stimulus's generated bindings with explicit test targets. Keep
// the real controller and storage module for the account/payment handoff.
const storeUrl = new URL("../../app/javascript/campaign_media_store.js", import.meta.url).href
const controllerSource = readFileSync(new URL("../../app/javascript/controllers/campaign_form_controller.js", import.meta.url), "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  .replace('from "campaign_media_store"', `from ${JSON.stringify(storeUrl)}`)
const { default: CampaignForm } = await import(`data:text/javascript;base64,${Buffer.from(controllerSource).toString("base64")}`)

// A small IndexedDB protocol double tests namespace/transfer failures without
// a browser or live account. The system tests exercise native IndexedDB.
function storageDouble() {
  const records = new Map()
  const state = { failKey: null }
  const db = {
    close() {},
    transaction() {
      const tx = { pending: 0, failed: false }
      const request = action => {
        const operation = {}
        tx.pending++
        queueMicrotask(() => {
          try { operation.result = action(); operation.onsuccess?.() }
          catch (error) { tx.failed = true; tx.error = error; tx.onerror?.() }
          finally { if (--tx.pending === 0 && !tx.failed) queueMicrotask(() => tx.oncomplete?.()) }
        })
        return operation
      }
      tx.objectStore = () => ({
        get: key => request(() => records.get(key)),
        put: value => request(() => {
          if (state.failKey === value.key) throw new Error("quota exceeded")
          records.set(value.key, value)
          return value.key
        }),
        delete: key => request(() => records.delete(key)),
        openCursor: () => request(() => null)
      })
      return tx
    }
  }
  globalThis.indexedDB = { open() {
    const operation = {}
    queueMicrotask(() => { operation.result = db; operation.onsuccess?.() })
    return operation
  } }
  return state
}

test("draft fields preserve Unicode, line breaks, selected radios and unchecked flags", () => {
  const elements = [
    { name: "campaign[business_name]", type: "text", value: "Café São João ☕" },
    { name: "campaign[offer]", type: "textarea", value: "Black Friday\nCafé por R$ 12" },
    { name: "campaign[vocal_gender]", type: "radio", value: "male", checked: false },
    { name: "campaign[vocal_gender]", type: "radio", value: "female", checked: true },
    { name: "campaign[show_cta]", type: "hidden", value: "0" },
    { name: "campaign[remove_logo]", type: "checkbox", value: "1", checked: false },
    { name: "authenticity_token", type: "hidden", value: "never-copy-csrf" },
    { name: "user[password]", type: "password", value: "never-copy-password" },
    { name: "campaign[photos][]", type: "file", value: "file" }
  ]
  const fields = draftFields({ elements })
  assert.equal(fields.length, 4)
  const destination = elements.map(input => ({ ...input, checked: false, value: ["radio", "checkbox"].includes(input.type) ? input.value : "" }))
  restoreDraftFields({ elements: destination }, [...fields, ["authenticity_token", "injected"], ["user[password]", "injected"]])
  assert.equal(destination[0].value, "Café São João ☕")
  assert.equal(destination[1].value, "Black Friday\nCafé por R$ 12")
  assert.equal(destination[2].checked, false)
  assert.equal(destination[3].checked, true)
  assert.equal(destination[4].value, "0")
  assert.equal(destination[6].value, "")
  assert.equal(destination[7].value, "")
})

test("account handoff keeps photos, order and fields then removes the anonymous copy", async () => {
  storageDouble()
  const token = "draft-one"
  const first = new File(["photo-first"], "first.png", { type: "image/png" })
  const second = new File(["photo-second"], "second.jpg", { type: "image/jpeg" })
  await saveMedia("guest-one", token, { photos: [second, first], logo: null, step: 2, fields: [["campaign[creation_token]", token], ["campaign[offer]", "Oferta da loja"]] })
  await claimDraft("guest-one", token, "customer-one")
  assert.equal(await loadMedia("guest-one", token), undefined)
  const saved = await loadMedia("customer-one", token)
  assert.deepEqual(saved.photos.map(file => file.name), ["second.jpg", "first.png"])
  assert.equal(await saved.photos[0].text(), "photo-second")
  assert.equal(saved.step, 2)
  assert.equal(saved.fields[1][1], "Oferta da loja")
  assert.equal(await loadMedia("customer-two", token), undefined)
})

test("failed storage transfer preserves the original and allows a safe retry", async () => {
  const storage = storageDouble()
  const token = "draft-two"
  await saveMedia("guest-two", token, { photos: [new File(["photo"], "photo.png")], fields: [["campaign[creation_token]", token]] })
  storage.failKey = `customer-two:${token}`
  await assert.rejects(claimDraft("guest-two", token, "customer-two"), /quota/)
  assert.equal((await loadMedia("guest-two", token)).photos.length, 1)
  storage.failKey = null
  await claimDraft("guest-two", token, "customer-two")
  assert.equal((await loadMedia("customer-two", token)).photos.length, 1)
})

test("a resumed handoff reuses the owned draft without needing the guest copy", async () => {
  storageDouble()
  await saveMedia("customer", "token", { photos: [], fields: [["campaign[creation_token]", "token"]] })
  assert.equal((await claimDraft("guest", "token", "customer")).photos.length, 0)
})

test("missing or mismatched drafts cannot be restored into an account", async () => {
  storageDouble()
  await assert.rejects(claimDraft("guest", "missing", "customer"), /indisponível/)
  await saveMedia("guest", "different", { photos: [], fields: [["campaign[creation_token]", "other"]] })
  await assert.rejects(claimDraft("guest", "different", "customer"), /indisponível/)
})

function resumeController({ guest = false, checkout = true, connected = true } = {}) {
  const controller = new CampaignForm()
  Object.assign(controller, {
    initialStepValue: 2, hasStepTarget: false, hasCtaChoiceTarget: false,
    hasDraftOwnerValue: true, hasDraftTokenValue: true, draftOwnerValue: "guest-controller", draftTokenValue: "controller-token",
    resumeCheckoutValue: checkout, guestValue: guest, stepTargets: [{}, {}, {}], hasSubmitTarget: true,
    hasSubmitLabelTarget: false, submitTarget: { dataset: {}, value: "Continuar", disabled: false },
    element: { dataset: { mediaOwner: guest ? "guest-controller" : "owned-controller" }, elements: [], isConnected: connected,
      querySelector: () => null, requestSubmit: () => { controller.checkoutRequests = (controller.checkoutRequests || 0) + 1 } },
    watchStage() {}, preview() {}, logo() {}, show() {},
    async restoreMedia(media) { this.restoredPhotos = media.photos },
    mediaError(message) { this.restoreError = message }
  })
  return controller
}

async function saveControllerDraft() {
  await saveMedia("guest-controller", "controller-token", {
    photos: [new File(["kept-photo"], "kept-photo.png")], step: 2,
    fields: [["campaign[creation_token]", "controller-token"], ["campaign[offer]", "Oferta preservada"]]
  })
}

test("authenticated continuation requests checkout only after its photos are restored", async () => {
  storageDouble()
  await saveControllerDraft()
  const controller = resumeController()
  controller.connect()
  await controller.mediaReady
  assert.equal(controller.restoredPhotos[0].name, "kept-photo.png")
  assert.equal(controller.checkoutRequests, 1)
  assert.equal(controller.index, 2)
})

test("missing drafts never automatically request payment", async () => {
  storageDouble()
  const controller = resumeController()
  controller.connect()
  await controller.mediaReady
  assert.equal(controller.checkoutRequests, undefined)
  assert.equal(controller.index, 0)
  assert.match(controller.restoreError, /nenhum pagamento foi iniciado/)
})

test("a credit balance waits for confirmation after restoring the draft", async () => {
  storageDouble()
  await saveControllerDraft()
  const controller = resumeController({ checkout: false })
  controller.connect()
  await controller.mediaReady
  assert.equal(controller.checkoutRequests, undefined)
  assert.equal(controller.restoredPhotos.length, 1)
  assert.equal(controller.index, 2)
})

test("returning to edit anonymously never requests payment", async () => {
  storageDouble()
  await saveControllerDraft()
  const controller = resumeController({ guest: true })
  controller.connect()
  await controller.mediaReady
  assert.equal(controller.checkoutRequests, undefined)
  assert.equal(controller.restoredPhotos.length, 1)
})

test("a page that has been left does not submit a restored draft", async () => {
  storageDouble()
  await saveControllerDraft()
  const controller = resumeController({ connected: false })
  controller.connect()
  await controller.mediaReady
  assert.equal(controller.checkoutRequests, undefined)
})
