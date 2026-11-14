require "test_helper"

class SoundtrackSecurityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_paid)
    @order.soundtrack_input.destroy!
    @order.reload
  end

  test "paid Pro upload is bounded and queues the exact input once" do
    upload do |file|
      post order_soundtrack_input_path(@order), params: { soundtrack_input: { file: file } }
      assert_response :success
    end
    input = @order.reload.soundtrack_input
    assert input.processable_file?
    assert_enqueued_with(job: UploadSoundtrackInputToMurekaJob, args: [ @order.id, input.id ])
    assert_no_difference "SoundtrackInput.count" do
      get new_order_soundtrack_input_path(@order)
      assert_response :success
    end
    assert_equal input.id, @order.reload.soundtrack_input.id
    upload do |file|
      assert_no_difference [ "SoundtrackInput.count", "ActiveStorage::Blob.count" ] do
        assert_no_enqueued_jobs only: UploadSoundtrackInputToMurekaJob do
          post order_soundtrack_input_path(@order), params: { soundtrack_input: { file: file } }
          assert_response :unprocessable_entity
        end
      end
    end
    assert_equal input.id, @order.reload.soundtrack_input.id
  end

  test "pending Pro keeps attachment but provider upload waits for payment" do
    @order.update!(status: "pending")
    upload do |file|
      assert_no_enqueued_jobs only: UploadSoundtrackInputToMurekaJob do
        post order_soundtrack_input_path(@order), params: { soundtrack_input: { file: file } }
        assert_response :success
      end
    end
    input = @order.reload.soundtrack_input
    assert input.file.attached?
    assert_enqueued_with(job: UploadSoundtrackInputToMurekaJob, args: [ @order.id, input.id ]) { @order.mark_paid! }
  end

  test "both upload routes reject oversize files before blob persistence" do
    [ :dedicated, :chat ].each do |route|
      upload(size: SoundtrackInput::MAX_FILE_SIZE + 1) do |file|
        assert_no_difference [ "SoundtrackInput.count", "ActiveStorage::Blob.count" ] do
          assert_no_enqueued_jobs only: UploadSoundtrackInputToMurekaJob do
            post_upload(route, file)
            assert_response :unprocessable_entity
          end
        end
      end
    end
  end

  test "both routes reject unsupported content and malformed file parameters" do
    [ :dedicated, :chat ].each do |route|
      upload(type: "text/html") do |file|
        post_upload(route, file)
        assert_response :unprocessable_entity
      end
      post_upload(route, "forged-blob-id")
      assert_response :unprocessable_entity
    end
    assert_nil @order.reload.soundtrack_input
  end

  test "campaign and starter chat cannot use soundtrack mode during generation" do
    @order.update!(status: "music_generating", tier: "starter")
    upload do |file|
      assert_no_enqueued_jobs only: UploadSoundtrackInputToMurekaJob do
        post_upload(:chat, file)
        assert_response :unprocessable_entity
      end
    end
    @order.create_campaign!(offer: "Oferta", business_name: "Loja", style: "animado", show_cta: false)
    @order.update!(tier: "pro")
    upload do |file|
      post_upload(:chat, file)
      assert_response :unprocessable_entity
      post_upload(:dedicated, file)
      assert_response :redirect
    end
    assert_nil @order.reload.soundtrack_input
  end

  test "paid chat still accepts an eligible Pro upload" do
    upload { |file| post_upload(:chat, file) }
    assert_response :success
    assert_enqueued_with(job: UploadSoundtrackInputToMurekaJob, args: [ @order.id, @order.reload.soundtrack_input.id ])
  end

  private

  def post_upload(route, file)
    if route == :chat
      post order_chat_path(@order), params: { mode: "soundtrack", file: file }
    else
      post order_soundtrack_input_path(@order), params: { soundtrack_input: { file: file } }
    end
  end

  def upload(size: nil, type: "image/png")
    Tempfile.create([ "soundtrack", ".png" ]) do |file|
      file.binmode
      file.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
      file.truncate(size) if size
      file.rewind
      yield Rack::Test::UploadedFile.new(file.path, type)
    end
  end
end
