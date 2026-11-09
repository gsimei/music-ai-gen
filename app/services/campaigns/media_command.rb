require "open3"
require "timeout"

module Campaigns
  class MediaCommand
    def self.run!(*command)
      output = nil
      Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, waiter|
        stdin.close
        errors = Thread.new { stderr.read }
        reader = Thread.new { stdout.read }
        begin
          Timeout.timeout(180) do
            raise "Falha na montagem do vídeo: #{errors.value.to_s.last(400)}" unless waiter.value.success?
            output = reader.value
          end
        rescue Timeout::Error
          Process.kill("KILL", -waiter.pid) rescue Errno::ESRCH
          raise "A montagem do vídeo demorou demais. Tente novamente."
        ensure
          errors.join
          reader.join
        end
      end
      output
    end
  end
end
