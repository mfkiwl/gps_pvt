# RTCM3 parser

require_relative 'util'

module GPS_PVT
class RTCM3
  def initialize(io)
    @io = io
    @buf = []
  end
  def RTCM3.checksum(packet, range = 0..-4)
    GPS_PVT::Util::CRC24Q::checksum(packet[range])
  end
  module Packet
    def decode(bits_list, offset = nil)
      Util::BitOp::extract(self, bits_list, offset || 24)
    end
    def message_number
      decode([12]).first
    end
    DataFrame = proc{
      unum_gen = proc{|n, sf|
        next [n, proc{|v| v}] unless sf
        [n, sf.kind_of?(Rational) ? proc{|v| (sf * v).to_f} : proc{|v| sf * v}]
      }
      num_gen = proc{|n, sf|
        lim = 1 << (n - 1)
        lim2 = lim << 1
        next [n, proc{|v| v >= lim ? v - lim2 : v}] unless sf
        [n, sf.kind_of?(Rational) ?
            proc{|v| v -= lim2 if v >= lim; (sf * v).to_f} :
            proc{|v| v -= lim2 if v >= lim; sf * v}]
      }
      num_sign_gen = proc{|n, sf|
        lim = 1 << (n - 1)
        next [n, proc{|v| v >= lim ? lim - v : v}] unless sf
        [n, sf.kind_of?(Rational) ?
            proc{|v| v = lim - v if v >= lim; (sf * v).to_f} :
            proc{|v| v = lim - v if v >= lim; sf * v}]
      }
      invalidate = proc{|orig, err|
        [orig[0], proc{|v| v == err ? nil : orig[1].call(v)}]
      }
      idx_list_gen = proc{|n, start|
        start ||= 0
        idx_list = (start...(start+n)).to_a.reverse
        [n, proc{|v| idx_list.inject([]){|res, idx|
          res.unshift(idx) if (v & 0x1) > 0
          break res unless (v >>= 1) > 0
          res
        } }]
      }
      sc2rad = 3.1415926535898
      df = { # {df_num => [bits, post_process] or generator_proc, ...}
        1 => proc{|n| n},
        2 => 12,
        3 => 12,
        4 => unum_gen.call(30, Rational(1, 1000)), # [sec]
        9 => 6,
        21 => 6,
        22 => 1,
        23 => 1,
        24 => 1,
        25 => num_gen.call(38, Rational(1, 10000)), # [m]
        34 => unum_gen.call(27, Rational(1, 1000)), # [sec]
        38 => 6,
        40 => 5,
        71 => 8,
        76 => 10,
        77 => proc{
          idx2meter = [
              2.40, 3.40, 4.85, 6.85, 9.65, 13.65, 24.00, 48.00,
              96.00, 192.00, 384.00, 768.00, 1536.00, 3072.00, 6144.00]
          [4, proc{|v| (v >= idx2meter.size) ? (idx2meter[-1] * 2) : idx2meter[v]}]
        }.call, # [m]
        78 => 2,
        79 => num_gen.call(14, Rational(sc2rad, 1 << 43)), # [rad/s]
        81 => unum_gen.call(16, 1 << 4), # [sec]
        82 => num_gen.call(8, Rational(1, 1 << 55)), # [s/s^2]
        83 => num_gen.call(16, Rational(1, 1 << 43)), # [s/s]
        84 => num_gen.call(22, Rational(1, 1 << 31)), # [sec]
        85 => 10,
        86 => num_gen.call(16, Rational(1, 1 << 5)), # [m]
        87 => num_gen.call(16, Rational(sc2rad, 1 << 43)), # [rad/s]
        88 => num_gen.call(32, Rational(sc2rad, 1 << 31)), # [rad/s]
        89 => num_gen.call(16, Rational(1, 1 << 29)), # [rad]
        90 => unum_gen.call(32, Rational(1, 1 << 33)),
        91 => num_gen.call(16, Rational(1, 1 << 29)), # [rad]
        92 => unum_gen.call(32, Rational(1, 1 << 19)), # [m^1/2]
        93 => unum_gen.call(16, 1 << 4), # [sec]
        94 => num_gen.call(16, Rational(1, 1 << 29)), # [rad]
        95 => num_gen.call(32, Rational(sc2rad, 1 << 31)), # [rad/s]
        96 => num_gen.call(16, Rational(1, 1 << 29)), # [rad]
        97 => num_gen.call(32, Rational(sc2rad, 1 << 31)), # [rad/s]
        98 => num_gen.call(16, Rational(1, 1 << 5)), # [m]
        99 => num_gen.call(32, Rational(sc2rad, 1 << 31)), # [rad]
        100 => num_gen.call(24, Rational(sc2rad, 1 << 43)), # [rad/s]
        101 => num_gen.call(8, Rational(1, 1 << 31)), # [sec]
        102 => 6,
        103 => 1,
        104 => 1,
        105 => 1,
        106 => [2, proc{|v| [0, 30, 45, 60][v] * 60}], # [s]
        107 => [12, proc{|v|
          hh, mm, ss = [v >> 7, (v & 0x7E) >> 1, (v & 0x1) > 0 ? 30 : 0]
          hh * 3600 + mm * 60 + ss # [sec]
        }],
        108 => 1,
        109 => 1,
        110 => unum_gen.call(7, 15 * 60), # [sec]
        111 => num_sign_gen.call(24, Rational(1000, 1 << 20)), # [m/s]
        112 => num_sign_gen.call(27, Rational(1000, 1 << 11)), # [m]
        113 => num_sign_gen.call(5, Rational(1000, 1 << 30)), # [m/s^2]
        120 => 1,
        121 => num_sign_gen.call(11, Rational(1, 1 << 40)),
        122 => 2, # (M)
        123 => 1, # (M)
        124 => num_sign_gen.call(22, Rational(1, 1 << 30)), # [sec]
        125 => num_sign_gen.call(5, Rational(1, 1 << 30)), # [sec], (M)
        126 => 5, # [day]
        127 => 1, # (M)
        128 => [4, proc{|v|
          [1, 2, 2.5, 4, 5, 7, 10, 12, 14, 16, 32, 64, 128, 256, 512, 1024][v]
        }], # [m] (M)
        129 => 11, # [day]
        130 => 2, # 1 => GLONASS-M, (M) fields are active 
        131 => 1,
        132 => 11, # [day]
        133 => num_sign_gen.call(32, Rational(1, 1 << 31)), # [sec]
        134 => 5, # [4year], (M)
        135 => num_sign_gen.call(22, Rational(1, 1 << 30)), # [sec], (M)
        136 => 1, # (M)
        137 => 1,
        141 => 1,
        142 => 1,
        248 => 30,
        364 => 2,
        393 => 1,
        394 => idx_list_gen.call(64, 1),
        395 => idx_list_gen.call(32, 1),
        396 => proc{|df394, df395|
          x_list = df394.product(df395)
          idx_list = idx_list_gen.call(x_list.size)[1]
          [x_list.size, proc{|v| x_list.values_at(*idx_list.call(v))}]
        },
        397 => invalidate.call(unum_gen.call(8, Rational(1, 1000)), 0xFF), # [sec]
        398 => unum_gen.call(10, Rational(1, 1000 << 10)), # [sec]
        399 => invalidate.call(num_gen.call(14), 0x2000), # [m/s]
        404 => invalidate.call(num_gen.call(15, Rational(1, 10000)), 0x4000), # [m/s]
        405 => invalidate.call(num_gen.call(20, Rational(1, 1000 << 29)), 0x80000), # [sec]
        406 => invalidate.call(num_gen.call(24, Rational(1, 1000 << 31)), 0x800000), # [sec]
        407 => 10,
        408 => unum_gen.call(10, Rational(1, 1 << 4)), # [dB-Hz]
        409 => 3,
        411 => 2,
        412 => 2,
        416 => 3,
        417 => 1,
        418 => 3,
        420 => 1,
        429 => 4,
        :uint => proc{|n| n},
      }
      df[27] = df[26] = df[25]
      df[117] = df[114] = df[111]
      df[118] = df[115] = df[112]
      df[119] = df[116] = df[113]
      {430..433 => 81..84, 434 => 71, 435..449 => 86..100, 450 => 79, 451 => 78,
          452 => 76, 453 => 77, 454 => 102, 455 => 101, 456 => 85, 457 => 137}.each{|dst, src|
        # QZSS ephemeris => GPS
        src = (src.to_a rescue [src]).flatten
        (dst.to_a rescue ([dst] * src.size)).flatten.zip(src).each{|i, j| df[i] = df[j]}
      }
      df.define_singleton_method(:generate_prop){|idx_list|
        hash = Hash[*([:bits, :op].collect.with_index{|k, i|
          [k, idx_list.collect{|idx, *args|
            case prop = self[idx]
            when Proc; prop = prop.call(*args)
            end
            [prop].flatten(1)[i]
          }]
        }.flatten(1))].merge({:df => idx_list})
        hash[:bits_total] = hash[:bits].inject{|a, b| a + b}
        hash
      }
      df
    }.call
    MessageType = Hash[*({
      1005 => [2, 3, 21, 22, 23, 24, 141, 25, 142, [1, 1], 26, 364, 27],
      1019 => [2, 9, (76..79).to_a, 71, (81..103).to_a, 137].flatten, # 488 bits @see Table 3.5-21
      1020 => [2, 38, 40, (104..136).to_a].flatten, # 360 bits @see Table 3.5-21
      1044 => [2, (429..457).to_a].flatten, # 485 bits
      1077 => [2, 3, 4, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-78
      1087 => [2, 3, 416, 34, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-93
      1097 => [2, 3, 248, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-98
      1117 => [2, 3, 4, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits
    }.collect{|mt, df_list| [mt, DataFrame.generate_prop(df_list)]}.flatten(1))]
    module GPS_Ephemeris
      KEY2IDX = {:svid => 1, :WN => 2, :URA => 3, :dot_i0 => 5, :iode => 6, :t_oc => 7,
          :a_f2 => 8, :a_f1 => 9, :a_f0 => 10, :iodc => 11, :c_rs => 12, :delta_n => 13,
          :M0 => 14, :c_uc => 15, :e => 16, :c_us => 17, :sqrt_A => 18, :t_oe => 19, :c_ic => 20,
          :Omega0 => 21, :c_is => 22, :i0 => 23, :c_rc => 24, :omega => 25, :dot_Omega0 => 26,
          :t_GD => 27, :SV_health => 28}
      def params
        # TODO WN is truncated to 0-1023
        res = Hash[*(KEY2IDX.collect{|k, i| [k, self[i][0]]}.flatten(1))]
        res[:fit_interval] = ((self[29] == 0) ? 4 : case res[:iodc] 
          when 240..247; 8
          when 248..255, 496; 14
          when 497..503; 26
          when 504..510; 50
          when 511, 752..756; 74
          when 757..763; 98
          when 764..767, 1088..1010; 122
          when 1011..1020; 146
          else; 6
        end) * 60 * 60
        res
      end
    end
    module GLONASS_Ephemeris
      def params
        # TODO insufficient: :n => ?(String4); extra: :P3
        # TODO generate time with t_b, N_T, NA, N_4
        # TODO GPS.i is required to modify to generate EPhemeris_with_GPS_Time
        k_i =  {:svid => 1, :freq_ch => 2, :P1 => 5, :t_k => 6, :B_n => 7, :P2 => 8, :t_b => 9,
            :xn_dot => 10, :xn => 11, :xn_ddot => 12,
            :yn_dot => 13, :yn => 14, :yn_ddot => 15,
            :zn_dot => 16, :zn => 17, :zn_ddot => 18,
            :P3 => 19, :gamma_n => 20, :p => 21, :tau_n => 23, :delta_tau_n => 24, :E_n => 25,
            :P4 => 26, :F_T => 27, :N_T => 28, :M => 29}
        k_i.merge!({:NA => 31, :tau_c => 32, :N_4 => 33, :tau_GPS => 34}) if self[30][0] == 1 # check DF131
        res = Hash[*(k_i.collect{|k, i| [k, self[i][0]]}.flatten(1))]
        res.reject!{|k, v|
          case k
          when :N_T; v == 0
          when :p, :delta_tau_n, :P4, :F_T, :N_4, :tau_GPS; true # TODO sometimes delta_tau_n is valid?
          else; false
          end
        } if (res[:M] != 1) # check DF130
        res
      end
    end
    module QZSS_Ephemeris
      KEY2IDX = {:svid => 1, :t_oc => 2, :a_f2 => 3, :a_f1 => 4, :a_f0 => 5,
          :iode => 6, :c_rs => 7, :delta_n => 8, :M0 => 9, :c_uc => 10, :e => 11,
          :c_us => 12, :sqrt_A => 13, :t_oe => 14, :c_ic => 15, :Omega0 => 16,
          :c_is => 17, :i0 => 18, :c_rc => 19, :omega => 20, :dot_Omega0 => 21,
          :dot_i0 => 22, :WN => 24, :URA => 25, :SV_health => 26,
          :t_GD => 27, :iodc => 28}
      def params
        # TODO PRN = svid + 192, WN is truncated to 0-1023
        res = Hash[*(KEY2IDX.collect{|k, i| [k, self[i][0]]}.flatten(1))]
        res[:fit_interval] = (self[29] == 0) ? 2 * 60 * 60 : nil # TODO how to treat fit_interval > 2 hrs
        res
      end
    end
    module MSM_Header
      def more_data?
        self.find{|v| v[1] == 393}[0] == 1
      end
    end
    module MSM7
      SPEED_OF_LIGHT = 299_792_458
      def ranges
        idx_sat = self.find_index{|v| v[1] == 394}
        sats = self[idx_sat][0]
        nsat = sats.size
        cells = self[idx_sat + 2][0] # DF396
        ncell = cells.size
        offset = idx_sat + 3
        range_rough = self[offset, nsat] # DF397
        range_rough2 = self[offset + (nsat * 2), nsat] # DF398
        delta_rough = self[offset + (nsat * 3), nsat] # DF399
        range_fine = self[offset + (nsat * 4), ncell] # DF405
        phase_fine = self[offset + (nsat * 4) + (ncell * 1), ncell] # DF406
        delta_fine = self[offset + (nsat * 4) + (ncell * 5), ncell] # DF404
        Hash[*([:pseudo_range, :phase_range, :phase_range_rate, :sat_sig].zip(
            cells.collect.with_index{|(sat, sig), i|
              i2 = sats.find_index(sat)
            rough_ms = (range_rough2[i2][0] + range_rough[i2][0]) rescue nil
              [(((range_fine[i][0] + rough_ms) * SPEED_OF_LIGHT) rescue nil),
                  (((phase_fine[i][0] + rough_ms) * SPEED_OF_LIGHT) rescue nil),
                  ((delta_fine[i][0] + delta_rough[i2][0]) rescue nil)]
            }.transpose + [cells]).flatten(1))]
      end
    end
    def parse
      msg_num = message_number
      return nil unless (mt = MessageType[msg_num])
      # return [[value, df], ...]
      values, df_list, attributes = [[], [], []]
      add_proc = proc{|target, offset|
        values += decode(target[:bits], offset).zip(target[:op]).collect{|v, op|
          op ? op.call(v) : v
        }
        df_list += target[:df]
      }
      add_proc.call(mt)
      case msg_num
      when 1019
        attributes << GPS_Ephemeris
      when 1020
        attributes << GLONASS_Ephemeris
      when 1044
        attributes << QZSS_Ephemeris
      when 1077, 1087, 1097, 1117
        # 1077(GPS), 1087(GLONASS), 1097(GALILEO), 1117(QZSS)
        attributes << MSM7
        nsat, nsig = [-2, -1].collect{|i| values[i].size}
        offset = 24 + mt[:bits_total]
        df396 = DataFrame.generate_prop([[396, values[-2], values[-1]]])
        add_proc.call(df396, offset)
        ncell = values[-1].size
        offset += df396[:bits_total]
        msm7_sat = DataFrame.generate_prop(
            ([[397, [:uint, 4], 398, 399]] * nsat).transpose.flatten(1))
        add_proc.call(msm7_sat, offset)
        offset += msm7_sat[:bits_total]
        msm7_sig = DataFrame.generate_prop(
            ([[405, 406, 407, 420, 408, 404]] * ncell).transpose.flatten(1))
        add_proc.call(msm7_sig, offset)
      end
      attributes << MSM_Header if (1070..1229).include?(msg_num)
      res = values.zip(df_list)
      attributes.empty? ? res : res.extend(*attributes)
    end
  end
  def read_packet
    while !@io.eof?
      if @buf.size < 6 then
        @buf += @io.read(6 - @buf.size).unpack('C*')
        return nil if @buf.size < 6
      end
      
      if @buf[0] != 0xD3 then
        @buf.shift
        next
      elsif (@buf[1] & 0xFC) != 0x0 then
        @buf = @buf[2..-1]
        next
      end
      
      len = ((@buf[1] & 0x3) << 8) + @buf[2]
      if @buf.size < len + 6 then
        @buf += @io.read(len + 6 - @buf.size).unpack('C*')
        return nil if @buf.size < len + 6
      end
      
      #p (((["%02X"] * 3) + ["%06X"]).join(', '))%[*(@buf[(len + 3)..(len + 5)]) + [RTCM3::checksum(@buf)]]
      if "\0#{@buf[(len + 3)..(len + 5)].pack('C3')}".unpack('N')[0] != RTCM3::checksum(@buf) then
        @buf = @buf[2..-1]
        next
      end
      
      packet = @buf[0..(len + 5)]
      @buf = @buf[(len + 6)..-1]
      
      return packet.extend(Packet)
    end
    return nil
  end
end
end