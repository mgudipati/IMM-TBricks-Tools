#!/usr/bin/env ruby

require 'csv'
require 'getoptlong'
require 'redis'
require 'json'

infile = ''
# specify the options we accept and initialize the option parser  
opts = GetoptLong.new(  
  [ "--infile", "-i", GetoptLong::REQUIRED_ARGUMENT ]
)  

# process the parsed options  
opts.each do |opt, arg|  
  case opt  
    when '--infile'  
      infile = arg  
  end  
end

# open redis db
$redisdb = Redis.new
$redisdb.select 0

# Process the NSCC basket composition file
# NSCC file layout is defined as follows:
# Header record describing the basket information
# => 01WREI           18383M47200220110624000000950005000000000000000291+0000000000000+0000162471058+0000000003249+0000000004503+0000005000000000000000000+
# Basket component records
# => 02AKR            0042391090002011062400000193WREI           18383M472002
# => 02ALX            0147521090002011062400000013WREI           18383M472002
# => ...
def parse_nscc_basket_composition_file( aFile )
  hash = Hash.new
  IO.foreach(aFile) do |line|
    line.chomp!
    case line[0..1]
      when '02' #Basket Component Detail
        #Component Symbol...Trading Symbol
        comp = line[2..16].strip
        if comp
          #Index Receipt Symbol...Trading Symbol
          etf = line[45..59].strip
          if etf
            if !hash.key?(comp)
              #create an array to hold the etf list for this component
              hash[comp] = Array.new
            end
            #append to the list...
            hash[comp] << etf
          end
        end
    end
  end

  return hash
end

components_h = Hash.new
if infile && File.exist?(infile)
  # use the dtcc file
  #comp_h = parse_nscc_basket_composition_file(infile)
else
  puts "File not found #{infile}, using redis db..."

  # use redis db
  keys = $redisdb.keys "DTCC:BASKET:*"
  keys.each do |key|
    bcusip = $redisdb.hget key, "IndexReceiptCUSIP"
    
    # collect all the components for this basket
    json = $redisdb.hget key, "Components"
    if !json then p key end
    if json
      hash = JSON.parse json
      hash.each do |ccusip, qty|
        if !components_h.key?(ccusip)
          components_h[ccusip] = Array.new
        end
        components_h[ccusip] << bcusip
      end
    end
  end
end # if File.exist?(infile)

#
# create a csv file of components and the etf baskets
#
# 100,A,ETFA, ETFB, ETFC,....
# 11,B,ETFD, EFTF,...
# 110,C,ETFA,ETFF,...
#
headers_a = [
  "Count",
  "Component Ticker",
  "ETF Baskets"
  ]
CSV.open("comp-etfs-report.csv", "wb", :headers => headers_a, :write_headers => true) do |csv|
  components_h.each do |key, value|
    csv << [value.length, key] + value
  end
end

=begin rdoc
 * Name: comp-etfs-report.rb
 * Description: Creates a report of security(s) and all the etfs it is part of.
 * Call using "ruby comp-etfs-report.rb [-i<input file>]"  
 * Author: Murthy Gudipati
 * Date: 12-Jul-2011
 * License: Saven Technologies Inc.
=end