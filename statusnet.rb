require 'open-uri'
require 'pp'
require 'ostruct'
require 'yaml'
require 'jekyll'
require 'hpricot'
require 'date'
require 'digest/md5'

# From http://api.rubyonrails.org/classes/ActiveSupport/CoreExtensions/Hash/Keys.html
class Hash
  def stringify_keys!
    keys.each do |key|
      self[key.to_s] = delete(key)
    end
    self
  end
end


def timeago(time, options = {})
   start_date = options.delete(:start_date) || Time.new
   date_format = options.delete(:date_format) || :default
   delta_minutes = (start_date.to_i - time.to_i).floor / 60
   if delta_minutes.abs <= (8724*60)       
     distance = distance_of_time_in_words(delta_minutes)       
     if delta_minutes < 0
        return "#{distance} from now"
     else
        return "#{distance} ago"
     end
   else
      return "on #{DateTime.now.to_formatted_s(date_format)}"
   end
 end
 def distance_of_time_in_words(minutes)
   case
     when minutes < 1
       "less than a minute"
     when minutes < 50
       pluralize(minutes, "minute")
     when minutes < 90
       "about one hour"
     when minutes < 1080
       "#{(minutes / 60).round} hours"
     when minutes < 1440
       "one day"
     when minutes < 2880
       "about one day"
     else
       "#{(minutes / 1440).round} days"
   end
 end




#
# Parses a status.net feed and returns items as an array.
#
class Statusnet
  DEFAULT_TTL = 600
 class << self
    def tag(host,uid, count = 15, ttl=DEFAULT_TTL)
      links = []
      url = "http://#{host}/api/statuses/user_timeline/#{uid}.rss"
      feed = Hpricot(open(url))
      feed.search("item").each do |i|
        item = OpenStruct.new
        item.link = i.at('link').next.to_s
        item.title = i.at('title').innerHTML
	a=i.at('pubdate').innerHTML rescue nil
	item.date=Date.parse(a)
	item.day = item.date
        item.description  = i.at('description').to_plain_text rescue nil

        links << item
      end

      links
    end
  end
end

# 
# Cached version of the Statusnet Jekyll tag.
#
class CachedStatusnet < Statusnet
  DEFAULT_TTL = 600
  CACHE_DIR = '_statusnet_cache'
  class << self
    def tag(host,uid, count = 15, ttl = DEFAULT_TTL)
      ttl = DEFAULT_TTL if ttl.nil?
      cache_key = "#{host}_#{uid}_#{count}"
      cache_file = File.join(CACHE_DIR, Digest::MD5.hexdigest(cache_key) + '.yml')
      FileUtils.mkdir_p(CACHE_DIR) if !File.directory?(CACHE_DIR)
      age_in_seconds = Time.now - File.stat(cache_file).mtime if File.exist?(cache_file)
      if age_in_seconds.nil? || age_in_seconds > ttl
        result = super(host, uid, count)
        File.open(cache_file, 'w') { |out| YAML.dump(result, out) }
      else
        result = YAML::load_file(cache_file)
      end
      result
    end
  end
end

#
# Usage:
#   
#      <ul class="statusnet-links">
#        {% statusnet username:x tag:design count:15 ttl:3600 %}
#        <li><a href="{{ item.link }}" title="{{ item.description }}" rel="external">{{ item.title }}</a></li>
#        {% endstatusnet %}
#      </ul>
#
# This will fetch the last 15 bookmarks tagged with 'design' from account 'x' and cache them for 3600 seconds.
# 
# Parameters:
#   username: statusnet username. For example, jebus.
#   tag:      statusnet tag. For example, design. Separate multiple tags with a plus character. 
#             For example, business+tosite, will fetch boomarks tagged both business and tosite.
#   count:    The number of bookmarks to fetch.
#   ttl:      The number of seconds to cache the feed. If not set, the feed will be fetched always.
#
module Jekyll
  class StatusnetTag < Liquid::Block

    include Liquid::StandardFilters
    Syntax = /(#{Liquid::QuotedFragment}+)?/ 

    def initialize(tag_name, markup, tokens)
      @variable_name = 'item'
      @attributes = {}
      
      # Parse parameters
      if markup =~ Syntax
        markup.scan(Liquid::TagAttributes) do |key, value|
          #p key + ":" + value
          @attributes[key] = value
        end
      else
        raise SyntaxError.new("Syntax Error in 'statusnet' - Valid syntax: statusnet host:x uid:x count:x]")
      end

      @ttl = @attributes.has_key?('ttl') ? @attributes['ttl'].to_i : nil
      @uid = @attributes['uid']
      @host = @attributes['host']
      @count = @attributes['count']
      @name = 'item'

      super
    end

    def render(context)
      context.registers[:statusnet] ||= Hash.new(0)
    
      if @ttl
        collection = CachedStatusnet.tag(@host, @uid, @count, @ttl)
      else
        collection = Statusnet.tag(@host, @uid, @count)
      end

      length = collection.length
      result = []
              
      # loop through found dents and render results
      context.stack do
        collection.each_with_index do |item, index|
          attrs = item.send('table')
          context[@variable_name] = attrs.stringify_keys! if attrs.size > 0
          context['forloop'] = {
            'name' => @name,
            'length' => length,
            'index' => index + 1,
            'index0' => index,
            'rindex' => length - index,
            'rindex0' => length - index -1,
            'first' => (index == 0),
            'last' => (index == length - 1) }

          result << render_all(@nodelist, context)
        end
      end
      result
    end
  end
end

Liquid::Template.register_tag('statusnet', Jekyll::StatusnetTag)

if __FILE__ == $0
  require 'test/unit'

  class TC_MyTest < Test::Unit::TestCase
    def setup
      @result = Statusnet::tag('37signals', 'svn', 5)
    end

    def test_size
      assert_equal(@result.size, 5)
    end

    def test_bookmark
      bookmark = @result.first
      assert_equal(bookmark.title, 'Mike Rundle: "I now realize why larger weblogs are switching to WordPress...')
      assert_equal(bookmark.description, "...when a site posts a dozen or more entries per day for the past few years, rebuilding the individual entry archives takes a long time. A long, long time. &amp;lt;strong&amp;gt;About 32 minutes each rebuild.&amp;lt;/strong&amp;gt;&amp;quot;")
      assert_equal(bookmark.link, "http://businesslogs.com/business_logs/launch_a_socialites_life.php")
    end
  end
end
