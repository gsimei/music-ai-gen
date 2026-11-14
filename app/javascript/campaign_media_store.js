const DATABASE = "virajingle-campaign-media"
const STORE = "drafts"
const MAX_AGE = 7 * 24 * 60 * 60 * 1000
const DRAFT_FIELDS = new Set(["business_name", "offer", "contact", "call_to_action", "show_cta", "cta_color", "style", "musical_genre", "vocal_gender", "music_notes", "remove_logo", "creation_token", "media_upload_token"].map(name => `campaign[${name}]`))

export function draftFields(form) {
  return Array.from(form.elements)
    .filter(input => DRAFT_FIELDS.has(input.name) && !["file", "submit"].includes(input.type))
    .filter(input => !["radio", "checkbox"].includes(input.type) || input.checked)
    .map(input => [input.name, input.value])
}

export function restoreDraftFields(form, fields) {
  for (const [name, value] of fields) {
    if (!DRAFT_FIELDS.has(name) || typeof value !== "string") continue
    for (const input of Array.from(form.elements).filter(input => input.name === name && input.type !== "file")) {
      if (["radio", "checkbox"].includes(input.type)) input.checked = input.value === value
      else input.value = value
    }
  }
}

export async function claimDraft(owner, token, destinationOwner) {
  const saved = await loadMedia(destinationOwner, token) || await loadMedia(owner, token)
  if (!saved || !Array.isArray(saved.fields) || !saved.fields.some(([name, value]) => name === "campaign[creation_token]" && value === token)) {
    throw new Error("Rascunho indisponível")
  }
  if (String(owner) !== String(destinationOwner)) {
    // Keep the original if quota/storage failures prevent the new copy.
    await saveMedia(destinationOwner, token, saved)
    await removeMedia(owner, token)
  }
  return saved
}

export function mediaToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  bytes[6] = (bytes[6] & 15) | 64
  bytes[8] = (bytes[8] & 63) | 128
  const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("")
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1)
    request.onupgradeneeded = () => request.result.createObjectStore(STORE, { keyPath: "key" })
    request.onerror = () => reject(request.error)
    request.onblocked = () => reject(new Error("Armazenamento indisponível"))
    request.onsuccess = () => resolve(request.result)
  })
}

async function transaction(mode, action) {
  const db = await open()
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, mode)
      const request = action(tx.objectStore(STORE))
      tx.oncomplete = () => resolve(request?.result)
      tx.onerror = () => reject(tx.error)
      tx.onabort = () => reject(tx.error || new Error("Armazenamento interrompido"))
    })
  } finally { db.close() }
}

export async function saveMedia(owner, token, media) {
  await transaction("readwrite", store => {
    const cursor = store.openCursor()
    cursor.onsuccess = () => {
      const item = cursor.result
      if (!item) return
      if (item.value.updatedAt < Date.now() - MAX_AGE) item.delete()
      item.continue()
    }
    return store.put({ ...media, key: `${owner}:${token}`, updatedAt: Date.now() })
  })
}

export async function loadMedia(owner, token) {
  if (!token) return null
  const media = await transaction("readonly", store => store.get(`${owner}:${token}`))
  if (media && media.updatedAt < Date.now() - MAX_AGE) {
    await removeMedia(owner, token)
    return null
  }
  return media
}

export function removeMedia(owner, token) {
  return transaction("readwrite", store => store.delete(`${owner}:${token}`))
}
