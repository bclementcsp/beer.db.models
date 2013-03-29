# encoding: UTF-8

module BeerDb

class Reader

  include LogUtils::Logging

  include BeerDb::Models

  attr_reader :include_path


  def initialize( include_path, opts = {} )
    @include_path = include_path
  end


  def load_setup( setup )
    ary = load_fixture_setup( setup )

    ary.each do |name|
      load( name )
    end
  end # method load_setup


  ## fix/todo: rename ??
  def load_fixture_setup( name )
    
   ## todo/fix: cleanup quick and dirty code
    
    path = "#{include_path}/#{name}.yml"

    logger.info "parsing data '#{name}' (#{path})..."

    text = File.read_utf8( path )
    
    hash = YAML.load( text )
    
    ### build up array for fixtures from hash
    
    ary = []
    
    hash.each do |key_wild, value_wild|
      key   = key_wild.to_s.strip
      
      logger.debug "yaml key:#{key_wild.class.name} >>#{key}<<, value:#{value_wild.class.name} >>#{value_wild}<<"
    
      if value_wild.kind_of?( String ) # assume single fixture name
        ary << value_wild
      elsif value_wild.kind_of?( Array ) # assume array of fixture names as strings
        ary = ary + value_wild
      else
        logger.error "unknow fixture type in setup (yaml key:#{key_wild.class.name} >>#{key}<<, value:#{value_wild.class.name} >>#{value_wild}<<); skipping"
      end
    end
    
    logger.debug "fixture setup:"
    logger.debug ary.to_json
    
    ary
  end # load_fixture_setup


  def load( name )

    if name =~ /\/([a-z]{2})\/beers/
      ## auto-add required country code (from folder structure)
      load_beers( $1, name )
    else
      logger.error "unknown beer.db fixture type >#{name}<"
      # todo/fix: exit w/ error
    end
  end
  

  def load_beers( country_key, name, more_values={} )
    country = Country.find_by_key!( country_key )
    logger.debug "Country #{country.key} >#{country.title} (#{country.code})<"

    more_values[ :country_id ] = country.id

    path = "#{include_path}/#{name}.txt"

    logger.info "parsing data '#{name}' (#{path})..."

    reader = ValuesReader.new( path, more_values )
    
    load_beers_worker( reader )

    Prop.create_from_fixture!( name, path )
  end


private


  def load_beers_worker( reader )

    ## NB: assumes active activerecord db connection
    ##

    reader.each_line do |attribs, values|
  
      value_tag_keys    = []
      
      ### check for "default" tags - that is, if present attribs[:tags] remove from hash
      
      if attribs[:tags].present?
        more_tag_keys = attribs[:tags].split('|')
        attribs.delete(:tags)

        ## unify; replace _w/ space; remove leading n trailing whitespace
        more_tag_keys = more_tag_keys.map do |key|
          key = key.gsub( '_', ' ' )
          key = key.strip
          key
        end

        value_tag_keys += more_tag_keys
      end


      ## check for optional values
      values.each_with_index do |value,index|
        if value =~ /^country:/   ## country:
          value_country_key = value[8..-1]  ## cut off country: prefix
          value_country = Country.find_by_key!( value_country_key )
          attribs[ :country_id ] = value_country.id
        elsif value =~ /^city:/   ## city:
          value_city_key = value[5..-1]  ## cut off city: prefix
          value_city = City.find_by_key!( value_city_key )
          attribs[ :city_id ] = value_city.id
        elsif (values.size==(index+1)) && value =~ /^[a-z0-9\|_ ]+$/   # tags must be last entry

          logger.debug "   found tags: >>#{value}<<"

          tag_keys = value.split('|')
  
          ## unify; replace _w/ space; remove leading n trailing whitespace
          tag_keys = tag_keys.map do |key|
            key = key.gsub( '_', ' ' )
            key = key.strip
            key
          end
          
          value_tag_keys += tag_keys
        else
          # issue warning: unknown type for value
          logger.warn "unknown type for value >#{value}<"
        end
      end # each value

      #  rec = Beer.find_by_key_and_country_id( attribs[ :key ], attribs[ :country_id] )
      rec = Beer.find_by_key( attribs[ :key ] )

      if rec.present?
        logger.debug "update Beer #{rec.id}-#{rec.key}:"
      else
        logger.debug "create Beer:"
        rec = Beer.new
      end
      
      logger.debug attribs.to_json

      rec.update_attributes!( attribs )

=begin
      ##################
      ## add taggings 

      if value_tag_keys.size > 0
        
          value_tag_keys.uniq!  # remove duplicates
          logger.debug "   adding #{value_tag_keys.size} taggings: >>#{value_tag_keys.join('|')}<<..."

          ### fix/todo: check tag_ids and only update diff (add/remove ids)

          value_tag_keys.each do |key|
            tag = Tag.find_by_key( key )
            if tag.nil?  # create tag if it doesn't exit
              logger.debug "   creating tag >#{key}<"
              tag = Tag.create!( key: key )
            end
            rec.tags << tag
          end
      end
=end
        
    end # each_line
            
  end # method load_beers_worker
  
end # class Reader
end # module BeerDb
