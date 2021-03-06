require 'socket'
require 'ssh_scan/client'
require 'net/ssh'

module SSHScan
  class ScanEngine

    def scan(opts)
      targets = opts[:targets]
      port = opts[:port]
      policy = opts[:policy_file]

      # Connect and get results (native)
      result = []
      targets.each_with_index do |target, index|
        client = SSHScan::Client.new(target, port)
        client.connect()
        result.push(client.get_kex_result())

        # Connect and get results (Net-SSH)
        net_ssh_session = Net::SSH::Transport::Session.new(target, :port => port)
        auth_session = Net::SSH::Authentication::Session.new(net_ssh_session, :auth_methods => ["none"])
        auth_session.authenticate("none", "test", "test")
        result[index]['auth_methods'] = auth_session.allowed_auth_methods
        host_key = net_ssh_session.host_keys.first
        net_ssh_session.close

        fingerprint_md5 = nil
        fingerprint_sha1 = nil
        fingerprint_sha256 = nil

        # only supporting RSA for the moment
        if host_key.is_a?(OpenSSL::PKey::RSA)
          data_string = OpenSSL::ASN1::Sequence([
            OpenSSL::ASN1::Integer.new(host_key.public_key.n),
            OpenSSL::ASN1::Integer.new(host_key.public_key.e)
          ])

          fingerprint_md5 = OpenSSL::Digest::MD5.hexdigest(data_string.to_der).scan(/../).join(':')
          fingerprint_sha1 = OpenSSL::Digest::SHA1.hexdigest(data_string.to_der).scan(/../).join(':')
          fingerprint_sha256 = OpenSSL::Digest::SHA256.hexdigest(data_string.to_der).scan(/../).join(':')
        else
          warn("Host key support for #{host_key.class} is not provided yet, fingerprints will not be available")
        end

        result[index]['fingerprints'] = {
          "md5" => fingerprint_md5,
          "sha1" => fingerprint_sha1,
          "sha256" => fingerprint_sha256,
        }

        # If policy defined, then add compliance results
        unless policy.nil?
          policy_mgr = SSHScan::PolicyManager.new(result[index], policy)
          result[index]['compliance'] = policy_mgr.compliance_results
        end
      end
      return result
    end
  end
end
