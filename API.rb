require "rubygems"
require "sinatra"
require "nokogiri"
require "open-uri"
require "json"
require "pp"
# require "haml"

enable :run
#enable :logging

get "/" do
  "welcome to hymnal.net (unofficial) API"
  
  # HAML ? documentation page
  
end

# classic hymns
get "/h/:id" do

  content_type :json
  
  # {id} must be an int between 1-1348
  hymnURL = "https://www.hymnal.net/en/hymn/h/#{params[:id]}"
  if Integer(params[:id]) > 0 and Integer(params[:id]) < 1349
    page = Nokogiri::HTML(open(hymnURL))

    # this will be exported to JSON
    hymn = Hash.new

    # pre-processing: eliminate <br> tags
    page.search("br").each do |n|
      n.replace("\n")
    end
    
    # extract hymn details w/ link (still needs to be implemented)
    # i.e. category, meter, composer, etc.
    
    # grab title
    hymn["title"] = page.css("div.main-content h1").text.strip()

    # extract lyrics
    lyrics = Hash.new
    # external site redirect - scrape witness-lee-hymns.org
    if page.css("div.lyrics a")[0]["href"].include?("witness-lee-hymns")
      # pad zeroes
      id = params[:id].rjust(4, "0")
      hymnURL = page.css("div.lyrics a")[0]["href"]
      page = Nokogiri::HTML(open(hymnURL))

      # grab author
      # details["Lyrics:"] = page.search("[text()*='AUTHOR:']").first.parent.text.gsub("AUTHOR:", "").strip

      for element in page.css("table[width='500'] tr td") do
        # only consider <td> if content is not whitespace
        unless element.text.gsub(/[[:space:]]/, "") == ""
          # if stanza number
          if element.text.to_i > 0
            # create a new entry with an empty list
            lyrics["stanza " + element.text.strip] = []
          # if chorus
          elsif element.text.gsub(/[[:space:]]/, "") == "Chorus"
            lyrics["chorus"] = []
          # if line
          else
            lyrics[lyrics.keys.last].push(clean_content(element.text))
          end
        end
      end
    # scrape hymnal.net
    else        
      for element in page.css("div.lyrics tr") do
        # verse numbers are denoted as <td>1</td>
        stanza_num = element.css('td div[class="stanza-num"]')
        chorus = element.css('td[class="chorus"]')
        if stanza_num[0]
          # store stanza as a list of lines
          p element.css('td')[1].text
          lyrics["stanza " + stanza_num[0].text] = clean_content(element.css('td')[1].text).split("\n")

        # chorus(es) are denoted in <td class="chorus"> tags
        elsif chorus[0]
          if !lyrics.has_key?(chorus[0]["class"])
            lyrics[chorus[0]["class"]] = clean_content(chorus[0].text).split("\n")
          # if there are multiple choruses:
          else
            # append some whitespace to create a unique key
            lyrics[chorus[0]["class"] + " " + String(1+lyrics.length/2)] = clean_content(chorus[0].text).split("\n")
          end
        end
      end
    end

    # Is there a new tune or alternate tune?
    # Doesn"t work for all cases yet
    tunes = Hash.new
    for element in page.css("div.hymn-related-songs div.list-group a")
      if element.text == "New Tune"
        tunes["New Tune"] = element["href"]
      end
      if element.text == "Alternate Tune"
        tunes["Alternate Tune"] = element["href"]
      end
    end

    # build and return JSON
    # hymn["details"] = details
    hymn["lyrics"] = lyrics
    unless tunes.empty?
      hymn["tunes"] = tunes
    end
    JSON.pretty_generate(hymn)
    
  else
    # throw error in JSON
    error = Hash.new
    error["error"] = "Sorry, there is no hymn with that number. Hymn should be within the 1-1348 range."
    error.to_json
  end

end

# new songs
get "/ns/:id" do
  #"New Songs"
  content_type :json

  #this method is not completely accurate since hymnal.net doesn"t always put the most recent songs on the front page
  #will need to add onto this
  most_recent = 0
  while most_recent == 0
    home = Nokogiri::HTML(open("https://www.hymnal.net/en/home"))
    home.search("br").each do |n|
      n.replace("\n")
    end
    for element in home.css("div.song-list a") do
      if element["href"].include?("/ns/")
        num = element["href"].gsub(/[^\d]/, "").to_i
        if num > most_recent
          most_recent = num
        end
      end
    end
  end

  puts most_recent

  nsURL = "https://www.hymnal.net/en/hymn/ns/#{params[:id]}"
  if Integer(params[:id]) > 0 and Integer(params[:id]) <= Integer(most_recent)
    page = Nokogiri::HTML(open(nsURL))

    # this will be exported to JSON
    newSong = Hash.new

    # pre-processing: eliminate <br> tags
    page.search("br").each do |n|
      n.replace("\n")
    end
    
    # extract song details w/ link (still needs to be implemented)
    # i.e. category, meter, composer, etc.

    lyrics = Hash.new
    # grab title
    newSong["title"] = page.css("div.main-content h1").text.strip()
    for element in page.css("div.lyrics tr") do
      # verse numbers are denoted as <td>1</td>
      stanza_num = element.css('td div[class="stanza-num"]')
      chorus = element.css('td[class="chorus"]')
      if stanza_num[0]
        # store stanza as a list of lines
        p element.css('td')[1].text
        lyrics["stanza " + stanza_num[0].text] = clean_content(element.css('td')[1].text).split("\n")

      # chorus(es) are denoted in <td class="chorus"> tags
      elsif chorus[0]
        if !lyrics.has_key?(chorus[0]["class"])
          lyrics[chorus[0]["class"]] = clean_content(chorus[0].text).split("\n")
        # if there are multiple choruses:
        else
          # append some whitespace to create a unique key
          lyrics[chorus[0]["class"] + " " + String(1+lyrics.length/2)] = clean_content(chorus[0].text).split("\n")
        end
      
      # no stanza or chorus classes, probably a one stanza song like ns/487
      else
        lyrics["stanza"] = clean_content(element.text).split("\n")
        lyrics["stanza"].delete_if do |line|
          if line == ""
            true
          end
        end
      end
    end

    # build and return JSON
    # newSong["details"] = details
    newSong["lyrics"] = lyrics
    JSON.pretty_generate(newSong)

  else
    # throw error in JSON
    error = Hash.new
    error["error"] = "Sorry, there is no new song with that number. The most recent new song known to the API has the number " + most_recent.to_s
    error.to_json
  end

end

# children
get "/c/:id" do
  content_type :json

  #this method is not completely accurate since hymnal.net doesn"t always put the most recent songs on the front page
  #will need to add onto this
  most_recent = 0
  while most_recent == 0
    home = Nokogiri::HTML(open("https://www.hymnal.net/en/home"))
    home.search("br").each do |n|
      n.replace("\n")
    end
    for element in home.css("div.song-list a") do
      if element["href"].include?("/c/")
        num = element["href"].gsub(/[^\d]/, "").to_i
        if num > most_recent
          most_recent = num
        end
      end
    end
  end

  puts most_recent

  childrenURL = "https://www.hymnal.net/en/hymn/c/#{params[:id]}"
  if Integer(params[:id]) > 0 and Integer(params[:id]) <= Integer(most_recent)
    page = Nokogiri::HTML(open(childrenURL))

    # this will be exported to JSON
    children = Hash.new

    # pre-processing: eliminate <br> tags
    page.search("br").each do |n|
      n.replace("\n")
    end
    
    # extract song details w/ link (still needs to be implemented)
    # i.e. category, meter, composer, etc.

    lyrics = Hash.new
    # grab title
    children["title"] = page.css("div.main-content h1").text.strip()
    for element in page.css("div.lyrics tr") do
      # verse numbers are denoted as <td>1</td>
      stanza_num = element.css('td div[class="stanza-num"]')
      chorus = element.css('td[class="chorus"]')
      if stanza_num[0]
        # store stanza as a list of lines
        lyrics["stanza " + stanza_num[0].text] = clean_content(element.css('td')[1].text).split("\n")

      # chorus(es) are denoted in <td class="chorus"> tags
      elsif chorus[0]
        if !lyrics.has_key?(chorus[0]["class"])
          lyrics[chorus[0]["class"]] = clean_content(chorus[0].text).split("\n")
        # if there are multiple choruses:
        else
          # append some whitespace to create a unique key
          lyrics[chorus[0]["class"] + " " + String(1+lyrics.length/2)] = clean_content(chorus[0].text).split("\n")
        end

      # children's songs don't always have stanza numbers like hymns and new songs
      elsif element.css('td').length > 1
        # use length of hash to keep track of stanza number (not the best way due to possibility of chorus)
        # but there are so few children's songs that it shouldn't matter
        # basically super hacky solution
        lyrics["stanza " + (lyrics.length + 1).to_s] = clean_content(element.css('td')[1].text).split("\n")
      end
    end

    copyright = Hash.new
    # grab copyright
    # puts clean_content(page.css('td[class="copyright"] small').text)
    copyright["copyright"] = clean_content(page.css('td[class="copyright"] small').text).gsub("\n", " ")

    # build and return JSON
    # children["details"] = details
    children["lyrics"] = lyrics
    children["copyright"] = copyright
    JSON.pretty_generate(children)

  else
    # throw error in JSON
    error = Hash.new
    error["error"] = "Sorry, there is no children's song with that number. The most recent new song known to the API has the number " + most_recent.to_s
    error.to_json
  end

end

# search results (still needs to be implemented)
get "/search/:string" do

end

# most recent
get "/most_recent" do
  #grabs most recent children and new song according to home page
  content_type :json

  recent = Hash.new

  recent_ns = 0
  recent_c = 0
  home = Nokogiri::HTML(open("https://www.hymnal.net/en/home"))
  home.search("br").each do |n|
    n.replace("\n")
  end

  for element in home.css("div.song-list a") do
    if element["href"].include?("/ns/")
      num = element["href"].gsub(/[^\d]/, "").to_i
      if num > recent_ns
        recent_ns = num
      end
    elsif element["href"].include?("/c/")
      num = element["href"].gsub(/[^\d]/, "").to_i
      if num > recent_c
        recent_c = num
      end
    end
  end

  recent["New Song"] = recent_ns
  recent["Children"] = recent_c
  JSON.pretty_generate(recent)
end

###################
###   DETAILS   ###
###################

# category or sub-category
get "category/:category" do
  
end

# sort hymns by key
get "/key/:key" do

end

# composer
get "/composer/:composer" do

end

# author
get "author/:author" do

end

# meter
get "author/:meter" do
  
end

# scripture reference
get "verse/:referece" do
  
end

def clean_content(text)
  return text.gsub(/[\u2018\u2019\u02bc\u055a\u07f4\u07f5\u0092]/, "'").gsub(/\u00a0/, "").gsub(/\u2014/, "-").gsub("  ", "")
end