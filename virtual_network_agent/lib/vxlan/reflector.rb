#
# Copyright (C) 2013 NEC Corporation
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

require 'open3'
require 'vxlan/configure'
require 'vxlan/log'

module Vxlan

  module Reflector

    class Vni
      def list
        vni = []
        Ctl.list_tunnel_endpoints().each_key do | key |
          if not vni.index[ key ]
            vni << key
          end
        end
        vni
      end

    end

    class TunnelEndpoint
      class << self
        def add vni, address, port = nil
          Ctl.add_tunnel_endpoint vni, address, port
        end

        def delete vni, address
          Ctl.delete_tunnel_endpoint vni, address
        end

        def list vni
          tunnel_endpoints = Ctl.list_tunnel_endpoints
          tunnel_endpoints.has_key?( vni ) and tunnel_endpoints[ vni ] or nil
        end

        def exists? vni, address
          tunnel_endpoints = list vni
          return false if tunnel_endpoints.nil?
          not tunnel_endpoints.select{ | each | each[ :ip ] == address.to_s }.empty?
        end

      end

    end

    class Ctl
      class << self
        def add_tunnel_endpoint vni, address, port = nil
          options = [ '--vni', vni, '--ip', address ]
          if not port.nil?
            options = options + [ '--port', port ]
          end
          reflectorctl '--add_tep', options
        end

        def delete_tunnel_endpoint vni, address
          options = [ '--vni', vni, '--ip', address ]
          reflectorctl '--del_tep', options
        end

        def list_tunnel_endpoints vni = nil
          tunnel_endpoints = Hash.new do | hash, key |
            hash[ key ] = []
          end
          line_no = 0
          options = []
          if not vni.nil?
            options = options + [ '--vni', vni ]
          end
          reflectorctl( '--list_tep', options ).split( "\n").each do | row |
            next if ( line_no = line_no + 1 ) <= 2 # skip header
            row = $1 if /^\s*(\S+(?:\s+\S+)*)\s*$/ =~ row
            vni, address, port, packet_count, octet_count = row.split( /\s*\|\s*/, 5 )
            port = 0 if port == '-'
            tunnel_endpoint = { :ip => address, :port => port.to_i, :packet_count => packet_count.to_i, :octet_count => octet_count.to_i }
            tunnel_endpoints[ vni.hex ].push tunnel_endpoint
          end
          tunnel_endpoints
        end

        private

        def config
          Vxlan::Configure.instance[ 'vxlan_tunnel_endpoint' ]
        end

        def reflectorctl command, options = []
          full_path = config[ 'reflectorctl' ]
          if %r,^/, !~ full_path
            full_path = File.dirname( __FILE__ ) + '/../../' + full_path
          end
          command_options = "#{ full_path } #{ command } #{ options.join ' ' }"
          logger.debug "reflectorctl: '#{ command_options }'"
          result = ""
          Open3.popen3( command_options ) do | stdin, stdout, stderr |
            stdin.close
            error = stderr.read
            result << stdout.read
            raise "Permission denied #{ full_path }" if /Permission denied/ =~ result
            raise "#{ result } #{ full_path }" if /Failed to/ =~ result
            raise "#{ error } #{ full_path }" unless error.length == 0
          end
          result
        end

        def logger
          Log.instance
        end

      end

    end

  end

end
