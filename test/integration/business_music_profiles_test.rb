require "test_helper"

class BusinessMusicProfilesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_pending)
    @campaign = Campaign.create!(order: @order, business_name: "Pizzaria da Vila", offer: "Pizza em dobro na terça",
      contact: "@vila", call_to_action: "Peça agora", style: "animado", musical_genre: "forro", vocal_gender: "female", music_notes: "Sanfona em destaque")
    @campaign.sync_briefing!
  end

  test "saving an identity and reusing it never copies the old offer or creates a generation" do
    assert_no_difference [ "Order.count", "MusicGeneration.count", "GenerationCost.count" ] do
      assert_difference "BusinessMusicProfile.count", 1 do
        post save_music_profile_campaign_path(@campaign)
      end
    end
    assert_redirected_to campaign_path(@campaign)
    profile = users(:customer_b2b).business_music_profiles.last
    assert_equal "female", profile.vocal_gender
    assert_equal "forro", profile.musical_genre
    assert_equal "Sanfona em destaque", profile.music_notes
    get new_campaign_path(music_profile_id: profile.id)
    assert_response :success
    assert_select 'input[name="campaign[business_name]"][value="Pizzaria da Vila"]'
    assert_select 'input[type="radio"][name="campaign[musical_genre]"][checked][value="forro"]'
    assert_select 'input[type="radio"][name="campaign[vocal_gender]"][checked][value="female"]'
    assert_select 'textarea[name="campaign[offer]"]', text: ""
    assert_select 'input[name="campaign[contact]"][value]', count: 0
    get new_campaign_path
    assert_select "a[href=?]", new_campaign_path(music_profile_id: profile.id)
  end

  test "same business updates only its own identity and campaign changes remain independent" do
    post save_music_profile_campaign_path(@campaign)
    profile = users(:customer_b2b).business_music_profiles.last
    @campaign.update!(business_name: "  PIZZARIA  DA VILA ", musical_genre: "pagode", vocal_gender: "male")
    assert_equal "forro", profile.reload.musical_genre
    assert_no_difference "BusinessMusicProfile.count" do
      post save_music_profile_campaign_path(@campaign)
    end
    assert_equal "pagode", profile.reload.musical_genre
    assert_equal "male", profile.vocal_gender
    assert_equal "PIZZARIA DA VILA", profile.business_name
    @campaign.update!(business_name: "Outra loja")
    assert_difference "BusinessMusicProfile.count", 1 do
      post save_music_profile_campaign_path(@campaign)
    end
  end

  test "saving after approval uses the chosen earlier round rather than latest campaign settings" do
    settings = @campaign.sound_settings
    generation = @order.music_generations.create!(iteration: 1, provider: "mureka", status: "completed", music_style: "forro", request_payload: { sound_settings: settings })
    @order.update!(status: "approved", approved_music_generation: generation, approved_variant: "a")
    @campaign.update!(musical_genre: "rock", vocal_gender: "male", music_notes: "Guitarra")
    post save_music_profile_campaign_path(@campaign)
    profile = users(:customer_b2b).business_music_profiles.last
    assert_equal "forro", profile.musical_genre
    assert_equal "female", profile.vocal_gender
    assert_equal "Sanfona em destaque", profile.music_notes
  end

  test "another account cannot load an identity or save from someone else's campaign" do
    post save_music_profile_campaign_path(@campaign)
    profile = users(:customer_b2b).business_music_profiles.last
    sign_out :user
    sign_in users(:customer_other)
    get new_campaign_path(music_profile_id: profile.id)
    assert_response :not_found
    sign_in users(:customer_other)
    assert_no_difference "BusinessMusicProfile.count" do
      post save_music_profile_campaign_path(@campaign)
    end
    assert_response :not_found
    sign_in users(:customer_other)
    get new_campaign_path
    assert_select "a[href=?]", new_campaign_path(music_profile_id: profile.id), count: 0
  end

  test "legacy approvals without direction snapshots do not silently save a different sound" do
    @order.update!(status: "approved")
    assert_no_difference "BusinessMusicProfile.count" do
      post save_music_profile_campaign_path(@campaign)
    end
    assert_redirected_to campaign_path(@campaign)
    assert flash[:alert].present?
  end

  test "rhythm previews are static assets and require no generation requests" do
    catalog = { "forro" => { url: "/demos/genres/forro-v1.mp3", label: "Forró" } }
    Campaigns::GenreSamples.stub(:catalog, catalog) do
      assert_no_difference [ "MusicGeneration.count", "GenerationCost.count" ] do
        get new_campaign_path
      end
      assert_select '[data-controller="genre-preview"]'
      assert_select 'audio[controls][preload="none"][data-genre-preview-target="player"]'
      assert_includes response.body, "Exemplo do ritmo, com voz ilustrativa"
      assert_includes response.body, "/demos/genres/forro-v1.mp3"
    end
  end
end
