raise 'Development asset preparation only' unless Rails.env.development?
require 'digest'
module SampleRequestDiagnostics
  def post_to_mureka
    response = super
    if response.code.to_i != 200
      body = JSON.parse(response.body) rescue {}
      puts({ http_status: response.code, error: body['error'] }.to_json)
      $stdout.flush
    end
    response
  end
end
MusicGenerator::MurekaClient.prepend(SampleRequestDiagnostics)
genre_key = ENV.fetch('SAMPLE_GENRE') { abort 'Set SAMPLE_GENRE to one of Campaign::GENRES (except auto)' }
abort 'Unknown genre' unless Campaign::GENRES.except('auto').key?(genre_key)
# Serialize maintenance invocations so concurrent runs cannot duplicate paid calls.
lock = File.open(Rails.root.join('tmp/genre-samples.lock'), 'w')
abort 'Another sample preparation is running' unless lock.flock(File::LOCK_EX | File::LOCK_NB)
manifest_path = Rails.root.join('config/genre_samples.json')
manifest = File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path)) : { 'version' => 1, 'samples' => {} }
persist = -> { File.write("#{manifest_path}.tmp", JSON.pretty_generate(manifest)); File.rename("#{manifest_path}.tmp", manifest_path) }
lyrics = "[Verse]\nHoje tem novidade, vem aproveitar!\n[Chorus]\nSua próxima oferta merece tocar!"
Campaign::GENRES.except('auto').select { |key, _| ENV['SAMPLE_GENRE'].blank? || key == ENV['SAMPLE_GENRE'] }.each do |key, genre|
  next if manifest['samples'].key?(key)
  prompt = "Brazilian Portuguese commercial jingle. #{genre[:prompt]}. Clearly recognizable genre, joyful, vocals immediately, no instrumental intro, no solos, short catchy hook, natural female singing voice. Original melody."
  entry = { 'status' => 'submitting', 'model' => Campaigns::MusicRounds::MODEL, 'n' => 1, 'gender' => 'female', 'prompt' => prompt, 'lyrics' => lyrics,
    'estimated_usd' => GenerationCost.song_price(Campaigns::MusicRounds::MODEL).to_f, 'pricing_version' => GenerationCost::PRICING_VERSION, 'usd_brl' => ENV.fetch('COST_USD_BRL', '6').to_f, 'requested_at' => Time.current.iso8601 }
  manifest['samples'][key] = entry
  persist.call
  result = MusicGenerator::MurekaClient.call(model: entry['model'], n: 1, prompt: prompt, lyrics: lyrics, gender: 'female')
  if result.failure?
    entry['status'] = 'submission_uncertain'; entry['error'] = result.errors.to_s; persist.call
    abort "#{key}: submission failed; inspect before retrying"
  end
  entry['job_id'] = result.value[:job_id]; entry['status'] = 'pending'; persist.call
  puts "Submitted #{key}"; $stdout.flush
end
80.times do
  pending = manifest['samples'].select { |_, entry| entry['status'] == 'pending' }
  break if pending.empty?
  pending.each do |key, entry|
    result = MusicGenerator::MurekaStatusClient.call(job_id: entry.fetch('job_id'))
    next unless result.success?
    if result.value[:status] == 'failed'
      entry['status'] = 'failed'; persist.call; puts "Failed #{key}"; next
    end
    next unless result.value[:status] == 'succeeded'
    choice = result.value.fetch(:choices).first
    Dir.mktmpdir('genre-sample-') do |dir|
      source = File.join(dir, 'original.mp3')
      Campaigns::AudioDownload.call(choice.fetch(:url), source)
      total = Float(Campaigns::MediaCommand.run!('ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', source))
      start = Campaigns::AudioExcerpt.start_seconds(lyrics_sync: { 'sections' => choice[:lyrics_sections] || [] }, track_duration: total)
      duration = [ 12.0, total - start ].min
      destination = Rails.root.join('public/demos/genres', "#{key}-v1.mp3")
      temporary = destination.sub_ext('.pending.mp3')
      Campaigns::MediaCommand.run!('ffmpeg', '-y', '-v', 'error', '-ss', start.to_s, '-i', source, '-t', duration.to_s,
        '-af', "loudnorm=I=-16:TP=-1.5:LRA=9,afade=t=in:d=0.08,afade=t=out:st=#{duration - 0.6}:d=0.6", '-ar', '44100', '-c:a', 'libmp3lame', '-b:a', '128k', temporary.to_s)
      File.rename(temporary, destination)
      entry.merge!('status' => 'ready', 'file' => "/demos/genres/#{key}-v1.mp3", 'duration_seconds' => duration, 'start_seconds' => start,
        'source_duration_seconds' => total, 'sha256' => Digest::SHA256.file(destination).hexdigest, 'generated_at' => Time.current.iso8601)
      persist.call; puts "Ready #{key} (#{duration}s)"; $stdout.flush
    end
  end
  sleep 10 if manifest['samples'].values.any? { |entry| entry['status'] == 'pending' }
end
puts manifest['samples'].transform_values { |entry| entry['status'] }.to_json
lock.close
