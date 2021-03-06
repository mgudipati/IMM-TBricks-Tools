#!/usr/bin/env ruby
require 'csv'
require 'builder'

# Security
class Security
  attr_accessor( :type )
  attr_accessor( :tickerSymbol )
  attr_accessor( :cusip )
  attr_accessor( :cik )
  attr_accessor( :isin )
  attr_accessor( :sedol )
  attr_accessor( :valoren )
  attr_accessor( :exchange )
  attr_accessor( :primaryMarket )
  attr_accessor( :name )
  attr_accessor( :companyName )
  attr_accessor( :shortName )
  attr_accessor( :industryCode )
  attr_accessor( :industryName )
  attr_accessor( :superSectorCode )
  attr_accessor( :superSectorName )
  attr_accessor( :sectorCode )
  attr_accessor( :sectorName )
  attr_accessor( :subSectorCode )
  attr_accessor( :subSectorName )
  attr_accessor( :issue )
  attr_accessor( :lot )
  attr_accessor( :boardLot )
  attr_accessor( :whenIssuedIndicator )
  attr_accessor( :foreignIndicator )
  attr_accessor( :exchangeIndicator )
  attr_accessor( :tradeDate )
  attr_accessor( :tape )

  def initialize( cusip )
    if cusip == "" or cusip == nil
      raise ArgumentError, "Invalid CUSIP Number!"
    end
    @cusip = cusip
  end  
end

# Basket
class Basket < Security
  attr_accessor( :componentCount )
  attr_accessor( :creationUnitsPerTrade )
  attr_accessor( :estimatedT1CashAmountPerCreationUnit )
  attr_accessor( :estimatedT1CashPerIndexReceipt )
  attr_accessor( :navPerCreationUnit )
  attr_accessor( :navPerIndexReceipt )
  attr_accessor( :totalCashAmount )
  attr_accessor( :totalSharesOutstanding )
  attr_accessor( :dividendAmount )
  attr_accessor( :cashIndicator )
  attr_reader( :components )

  # adds a component to the basket
  def add_component( aComponent )
    if aComponent
      if @components == nil then @components = Hash.new end
      @components[aComponent.cusip] = aComponent
    end
  end
end

# Basket Component
class BasketComponent < Security
  attr_accessor( :shareQuantity )
  attr_accessor( :newSecurityIndicator )
end

#
# Process the NSX symbol list file
# NSX symbol list file layout is defined as follows:
# Header record:
# => SYMBOL,CUSIP,TAPE,IS_TEST
#
# Data record:
# => TSU,88706P106,A,N
# 
def parse_nsx_symbol_list_file( aFile )
  securities = Array.new
  
  CSV.foreach(aFile, :quote_char => '"', :col_sep =>',', :row_sep => :auto, :headers => true) do |row|
    cusip = row.field('CUSIP').rjust(9, '0')
    test = row.field('IS_TEST') == 'N' ? false : true
  
    if cusip and !test
      # create a new security by passing the cusip as argument
      security = Security.new(cusip)
      
      # populate the attributes
      security.tickerSymbol = row.field('SYMBOL')
      security.tape = row.field('TAPE')

      # push it to the securities list
      securities.push(security)
    end
  end # CSV.foreach
  
  return securities
end

#
# Process the EDGE symbol list file
# EDGE symbol list file layout is defined as follows:
# Header record:
# => CUSIP,Symbol,Ext,Company Name,Primary Market,Round Lot Size,Min Order Qty
#
# Data record:
# => 00846U101,A,,AGILENT TECHNOLOGIES INC,NYSE,100,0
# 
def parse_edge_symbol_list_file( aFile )
  securities = Array.new
  
  CSV.foreach(aFile, :quote_char => '"', :col_sep =>',', :row_sep => :auto, :headers => true) do |row|
    cusip = row.field('CUSIP')
  
    if cusip
      # create a new security by passing the cusip as argument
      security = Security.new(cusip)
      
      # populate the attributes
      ext = row.field('Ext')
      security.tickerSymbol = row.field('Symbol') + (ext ? ".#{ext}" : "")
      security.type = ext
      security.primaryMarket = row.field('Primary Market')
      security.companyName = row.field('Company Name')
      security.boardLot = row.field('Round Lot Size')
      security.lot = row.field('Min Order Qty')      

      # push it to the securities list
      securities.push(security)
    end
  end # CSV.foreach
  
  return securities
end

#
# Process the nyse group symbol file
# Symbol file layout is defined as follows:
# Header record:
# => Symbol,CUSIP,CompanyName,NYSEGroupMarket,PrimaryMarket,IndustryCode,SuperSectorCode,SectorCode,SubSectorCode,IndustryName,SuperSectorName,SectorName,SubSectorName
#
# Data record:
# => AA,13817101,"ALCOA, INC",N,N,1000,1700,1750,1753,Basic Materials,Basic Resources,Industrial Metals & Mining,Aluminum
# 
def parse_nyse_grp_sym_file( aFile )
  securities_a = Array.new
  
  CSV.foreach(aFile, :quote_char => '"', :col_sep =>',', :row_sep => :auto, :headers => true) do |row|
    cusip = row.field('CUSIP').rjust(9, '0')
    if cusip
      # create a new security by passing the cusip as argument
      security = Security.new(cusip)

      # Symbology conversion...BRK A => BRK.A
      security.tickerSymbol = row.field('Symbol').sub(" ", ".")

      # populate the attributes
      security.exchange = row.field('NYSEGroupMarket')
      security.primaryMarket = row.field('PrimaryMarket')
      security.companyName = row.field('CompanyName')
      security.industryCode = row.field('IndustryCode')
      security.industryName = row.field('IndustryName')
      security.superSectorCode = row.field('SuperSectorCode')
      security.superSectorName = row.field('SuperSectorName')
      security.sectorCode = row.field('SectorCode')
      security.sectorName = row.field('SectorName')
      security.subSectorCode = row.field('SubSectorCode')
      security.subSectorName = row.field('SubSectorName')

      # push it to the securities list
      securities_a.push(security)
    end
  end # CSV.foreach
  
  return securities_a
end

# Process the NSCC basket composition file
# NSCC file layout is defined as follows:
# Header record describing the basket information
# => 01WREI           18383M47200220110624000000950005000000000000000291+0000000000000+0000162471058+0000000003249+0000000004503+0000005000000000000000000+
# Basket component records
# => 02AKR            0042391090002011062400000193WREI           18383M472002
# => 02ALX            0147521090002011062400000013WREI           18383M472002
# => ...
def parse_nscc_basket_composition_file( aFile )
  baskets_a = Array.new
  aBasket = nil
  numrec = 0
  
  IO.foreach(aFile) do |line|
    line.chomp!
    case line[0..1]
      when '01' #Basket Header
        numrec += 1

        #Index Receipt CUSIP...S&P assigned CUSIP
        aBasket = Basket.new(line[17..25].strip)

        #Index Receipt Symbol...Trading Symbol
        aBasket.tickerSymbol = line[2..16].strip

        #When Issued Indicator...0 = Regular Way 1 = When Issued
        aBasket.whenIssuedIndicator = line[26]
        
        #Foreign Indicator...0 = Domestic 1 = Foreign
        aBasket.foreignIndicator = line[27]
        
        #Exchange Indicator...0 = NYSE 1 = AMEX 2 = Other
        aBasket.exchangeIndicator = line[28]
        
        #Portfolio Trade Date...CCYYMMDD
        aBasket.tradeDate = line[29..36]
        
        #Component Count...99,999,999
        aBasket.componentCount = line[37..44].to_i
        
        #Create/Redeem Units per Trade...99,999,999
        aBasket.creationUnitsPerTrade = line[45..52].to_i

        #Estimated T-1 Cash Amount Per Creation Unit...999,999,999,999.99-
        aBasket.estimatedT1CashAmountPerCreationUnit = "#{line[53..64]}.#{line[65..66]}".to_f
        sign = line[67]
        if sign == '-' then aBasket.estimatedT1CashAmountPerCreationUnit *= -1 end
        
        #Estimated T-1 Cash Per Index Receipt...99,999,999,999.99
        aBasket.estimatedT1CashPerIndexReceipt = "#{line[68..78]}.#{line[79..80]}".to_f
        sign = line[81]
        if sign == '-' then aBasket.estimatedT1CashPerIndexReceipt *= -1 end
        
        #Net Asset Value Per Creation Unit...99,999,999,999.99
        aBasket.navPerCreationUnit = "#{line[82..92]}.#{line[93..94]}".to_f
        sign = line[95]
        if sign == '-' then aBasket.navPerCreationUnit *= -1 end

        #Net Asset Value Per Index Receipt...99,999,999,999.99
        aBasket.navPerIndexReceipt = "#{line[96..106]}.#{line[107..108]}".to_f
        sign = line[109]
        if sign == '-' then aBasket.navPerIndexReceipt *= -1 end
        
        #Total Cash Amount Per Creation Unit...99,999,999,999.99-
        aBasket.totalCashAmount = "#{line[110..120]}.#{line[121..122]}".to_f
        sign = line[123]
        if sign == '-' then aBasket.totalCashAmount *= -1 end

        #Total Shares Outstanding Per ETF...999,999,999,999
        aBasket.totalSharesOutstanding = line[124..135].to_i
        
        #Dividend Amount Per Index Receipt...99,999,999,999.99
        aBasket.dividendAmount = "#{line[136..146]}.#{line[147..148]}".to_f
        sign = line[149]
        if sign == '-' then aBasket.dividendAmount *= -1 end        

        #Cash / Security Indicator...  1 = Cash only 2 = Cash or components other – components only
        aBasket.cashIndicator = line[150]

        baskets_a << aBasket
      when '02' #Basket Component Detail
        numrec += 1
        
        #Component CUSIP...S&P assigned CUSIP
        aComponent = BasketComponent.new(line[17..25].strip)

        #Component Symbol...Trading Symbol
        aComponent.tickerSymbol = line[2..16].strip

        #When Issued Indicator...0 = Regular Way 1 = When Issued
        aComponent.whenIssuedIndicator = line[26]
        
        #Foreign Indicator...0 = Domestic 1 = Foreign
        aComponent.foreignIndicator = line[27]
        
        #Exchange Indicator...0 = NYSE 1 = AMEX 2 = Other
        aComponent.exchangeIndicator = line[28]
        
        #Portfolio Trade Date...CCYYMMDD
        aComponent.tradeDate = line[29..36]

        #Component Share Qty...99,999,999
        aComponent.shareQuantity = line[37..44].to_f

        #New Security Indicator...N = New CUSIP Space = Old CUSIP
        aComponent.newSecurityIndicator = line[72]
        
        aBasket.add_component(aComponent)
      when '09' #File Trailer
        numrec += 1
        # Record Count...99,999,999 Includes Records 01, 02, 09
        reccnt = line[37..44].to_i
        if numrec != reccnt
          puts "Error in DTCC File: records found:#{numrec} != records reported:#{reccnt}"
        end
    end
  end
  
  return baskets_a
end

# build the tbricks instruments xml file
#<?xml version="1.0" encoding="UTF-8"?>
#<resource name="instruments" type="application/x-instrument-reference-data+xml">
#  <instruments>
#    <instrument short_name="AADR" mnemonic="AADR" precedence="no" cfi="ESNTFR" price_format="decimal 2" deleted="no">
#      <xml type="fixml"/>
#      <groups/>
#      <identifiers>
#        <identifier venue="7c15c3c2-4a25-11e0-b2a1-2a7689193271" mic="BATS">
#          <fields>
#            <field name="exdestination" value="BATS"/>
#            <field name="symbol" value="AADR"/>
#          </fields>
#        </identifier>
#        <identifier venue="7c15c3c2-4a25-11e0-b2a1-2a7689193271" mic="EDGA">
#          <fields>
#            <field name="exdestination" value="EDGA"/>
#            <field name="symbol" value="AADR"/>
#          </fields>
#        </identifier>
#        <identifier venue="7c15c3c2-4a25-11e0-b2a1-2a7689193271" mic="EDGX">
#          <fields>
#            <field name="exdestination" value="EDGX"/>
#            <field name="symbol" value="AADR"/>
#          </fields>
#        </identifier>
#      </identifiers>
#    </instrument>
#    ...
#    ...
#  </instruments>
#</resource>
def create_tbricks_instruments_xml(outfile, securities, exchs)
  f = File.new(outfile, "w")
  xml = Builder::XmlMarkup.new(:target=>f, :indent=>2)
  xml.instruct!
  xml.resource( "name"=>"instruments", 
                "type"=>"application/x-instrument-reference-data+xml") {
    xml.instruments {
      # create an instrument node for each security
      securities.each do |aSecurity|
        # short_name should not be null
        short_name = aSecurity.shortName
        if short_name == nil then short_name = aSecurity.name end
        if short_name == nil then short_name = aSecurity.tickerSymbol end
        
        # to be consistent with baskets xml definition, ticker symbol is used for short_name
        xml.instrument( "short_name"=>aSecurity.tickerSymbol, 
                        "long_name"=>aSecurity.name,
                        "mnemonic"=>aSecurity.tickerSymbol, 
                        "precedence"=>"no", 
                        "cfi"=>"ESNTFR", 
                        "price_format"=>"decimal 2", 
                        "deleted"=>"no") {
          xml.xml("type"=>"fixml")
          xml.groups
          xml.identifiers {
            exchs.each do |aExch|
              sym = xref(aSecurity.cusip, aExch)
              if sym
                xml.identifier("venue"=>"7c15c3c2-4a25-11e0-b2a1-2a7689193271", "mic"=>aExch) {
                  xml.fields {
                    xml.field("name"=>"exdestination", "value"=>aExch)
                    xml.field("name"=>"symbol", "value"=>sym)
                  }
                }
              end
            end
          }
        }
      end
    }
  }
  f.close
end

# build the tbricks stub basket instruments xml file
#<?xml version="1.0" encoding="UTF-8"?>
#<resource name="instruments" type="application/x-instrument-reference-data+xml">
#  <instruments>
#    <instrument short_name="EDZ Basket" long_name="" mnemonic="" precedence="yes" cfi="ESXXXX" price_format="decimal 2" deleted="no">
#      <xml type="fixml"/>
#      <groups/>
#      <identifiers>
#        <identifier venue="c0c78852-efd6-11de-9fb8-dfdb5824b38d" mic="XXXX">
#          <fields>
#            <field name="symbol" value="EDZ"/>
#          </fields>
#        </identifier>
#      </identifiers>
#    </instrument>
#    ...
#    ...
#  </instruments>
#</resource>
def create_stub_basket_instruments_xml(outfile, baskets)
  f = File.new(outfile, "w")
  xml = Builder::XmlMarkup.new(:target=>f, :indent=>2)
  xml.instruct!
  xml.resource("name"=>"instruments", "type"=>"application/x-instrument-reference-data+xml") {
    xml.instruments {
      baskets.each do |aBasket|
        xml.instrument("short_name"=>"#{aBasket.tickerSymbol} Basket", "long_name"=>"", "mnemonic"=>"", "precedence"=>"yes", "cfi"=>"ESXXXX", "price_format"=>"decimal 2", "deleted"=>"no") {
          xml.xml("type"=>"fixml")
          xml.groups
          xml.identifiers {
            xml.identifier("venue"=>"c0c78852-efd6-11de-9fb8-dfdb5824b38d", "mic"=>"XXXX") {
              xml.fields {
                xml.field("name"=>"symbol", "value"=>aBasket.tickerSymbol)
              }
            }
          }
        }
      end
    }
  }
  f.close
end

# build the tbricks basket components xml file
# 
#<?xml version="1.0" encoding="UTF-8"?>
#<instruments>
#  <etf short_name="WREI">
#    <parameter name="netassetvalue" value="0.10"/>
#    <basket short_name="WREI Basket">
#      <legs>
#        <leg short_name="AMB" mic="BATS" ratio="0.0165"/>
#        <leg short_name="AKR" mic="BATS" ratio="0.0039"/>
#        ...
#        ...
#      </legs>
#    </basket>
#  </etf>
#</instruments>
def create_basket_components_xml(outfile, baskets)  
  f = File.new(outfile, "w")
  xml = Builder::XmlMarkup.new(:target=>f, :indent=>2)
  xml.instruct!
  xml.instruments {
    baskets.each do |aBasket|
      xml.etf("short_name"=>aBasket.tickerSymbol) {
        # NAV defined by Michael R. Conners...totalCashAmount/creationUnit
        nav = aBasket.totalCashAmount/aBasket.creationUnitsPerTrade
        xml.parameter("name"=>"netassetvalue", "value"=>sprintf("%.4f", nav))
        xml.basket("short_name"=>"#{aBasket.tickerSymbol} Basket") {
          xml.legs {
            aBasket.components.each do |aComponent|
              # Ratio defined by Michael R. Conners...shareQuantity/creationUnit
              ratio = aComponent.shareQuantity/aBasket.creationUnitsPerTrade
              xml.leg("short_name"=>aComponent.tickerSymbol, "mic"=>"BATS", "ratio"=>sprintf("%.4f", ratio))
            end
          }
        }
      } 
    end
  }
  f.close
end

# Process the xignite master securities file
# Xignite master securities file layout is defined as follows:
# => " Exchange"," Count"," Records Record Symbol"," Records Record CUSIP"," Records Record CIK"," Records Record ISIN"," Records Record SEDOL"," Records Record Valoren"," Records Record Exchange"," Records Record Name"," Records Record ShortName"," Records Record Issue"," Records Record Sector"," Records Record Industry"," Records Record LastUpdateDate",
# => For e.g. NYSE,3581,A,00846U101,0001090872,US00846U1016,2520153,901692,NYSE,"Agilent Technologies Inc.","Agilent Tech Inc","Common Stock",TECHNOLOGY,"Scientific & Technical Instruments",12/3/2005,
def parse_xignite_master_securities_file( aFile )
  securities = Array.new
  
  CSV.foreach(aFile, :quote_char => '"', :col_sep =>',', :row_sep => :auto, :headers => true) do |row|
    sym = row.field(' Records Record Symbol')
    if sym
      # create a new security by passing the ticker symbol as argument
      security = Security.new(sym)

      # populate the attributes
      security.cusip = row.field(' Records Record CUSIP')
      security.cik = row.field(' Records Record CIK')
      security.isin = row.field(' Records Record ISIN')
      security.sedol = row.field(' Records Record SEDOL')
      security.valoren = row.field(' Records Record Valoren')
      security.exchange = row.field(' Records Record Exchange')
      security.name = row.field(' Records Record Name')
      security.shortName = row.field(' Records Record ShortName')
      security.issue = row.field(' Records Record Issue')
      security.sector = row.field(' Records Record Sector')
      security.industry = row.field(' Records Record Industry')

      # push it to the securities list
      securities.push(security)
    end
  end # CSV.foreach
  
  return securities
end

# creates a securities map by ticker
def create_securities_map_by_ticker(securities)
  map = Hash.new
  securities.each do |aSecurity|
    # create a map keyed by ticker symbol
    if aSecurity.tickerSymbol
      map[aSecurity.tickerSymbol] = aSecurity
    end
  end
  
  return map
end

# creates securities map by cusip
def create_securities_map_by_cusip(securities)
  map = Hash.new
  securities.each do |aSecurity|
    # create a map keyed by cusip
    if aSecurity.cusip
      map[aSecurity.cusip] = aSecurity
    end
  end
  
  return map
end

# returns an exchange specific ticker symbol
def xref(cusip, exch)
  
end