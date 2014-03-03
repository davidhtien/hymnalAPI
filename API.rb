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
get "/hymn/:id" do

    content_type :json
    
    # {id} must be an int between 1-1348
    hymnURL = "http://hymnal.net/hymn.php/h/#{params[:id]}"
    if Integer(params[:id]) > 0 and Integer(params[:id]) < 1349
        page = Nokogiri::HTML(open(hymnURL))

        # this will be exported to JSON
        hymn = Hash.new

        # pre-processing: eliminate <br> tags
        page.search("br").each do |n|
            n.replace("\n")
        end
        
        # extract hymn details w/ link
        # i.e. category, meter, composer, etc.
        details = Hash.new
        for element in page.css("div#details li") do
            unless element.css("a").text.empty?
                details[element.css("span.key").text] = [element.css("a").text, element.css("a")[0]["href"]]
            else 
                details[element.css("span.key").text] = nil
            end
        end
        
        # extract lyrics
        lyrics = Hash.new
        # external site redirect - scrape witness-lee-hymns.org
        if page.css("div.lyrics p[class=info]").text == "View Lyrics (external site)"
            # pad zeroes
            id = params[:id].rjust(4, "0")
            hymnURL = page.css("div.lyrics p a")[0]["href"]
            page = Nokogiri::HTML(open(hymnURL))

            # grab title
            hymn["title"] = page.css("h1").text.strip()
            # grab author
            details["Lyrics:"] = page.search("[text()*="AUTHOR:"]").first.parent.text.gsub("AUTHOR:", "").strip

            # 
            for element in page.css("table[width="500"] tr td") do
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
                        lyrics[lyrics.keys.last].push(element.text)
                    end
                end
            end
        # scrape hymnal.net
        else        
            # grab title
            hymn["title"] = page.css("div.post-title span").text.strip()
            for element in page.css("div.lyrics li") do
                # verse numbers are denoted in <li value="1"> tags
                if element["value"]
                    # store stanza as a list of lines
                    lyrics["stanza " + element["value"]] = element.text.split("\n")

                # chorus(es) are denoted in <li class="chorus"> tags
                elsif element["class"]
                    if !lyrics.has_key?(element["class"])
                        lyrics[element["class"]] = element.text.split("\n")
                    # if there are multiple choruses:
                    else
                        # append some whitespace to create a unique key
                        lyrics[element["class"] + " " + String(1+lyrics.length/2)] = element.text.split("\n")
                    end
                end
            end
        end

        #Is there a new tune or alternate tune?
        #Doesn"t work for all cases yet
        tunes = Hash.new
        puts "got here"
        for element in page.css("div.relatedsongs li")
            puts element.css("a").text
            puts element.css("a").text.ascii_only?
            if element.css("a").text == "New Tune"
                tunes["New Tune"] = element.css("a")[0]["href"]
            end
            if element.css("a").text == "Alternate Tune"
                tunes["Alternate Tune"] = element.css("a")[0]["href"]
            end
        end

        # build and return JSON
        hymn["details"] = details
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
        home = Nokogiri::HTML(open("http://www.hymnal.net/en/home.php"))
        home.search("br").each do |n|
            n.replace("\n")
        end
        for element in home.css("ul.songsublist li") do
            if element.css("span.category").text.gsub!(/\P{ASCII}/, "") == "NewSongs"
                num = element.css("a")[0]["href"].gsub(/[^\d]/, "").to_i
                if num > most_recent
                    most_recent = num
                end
            end
        end
    end

    puts most_recent

    nsURL = "http://hymnal.net/hymn.php/ns/#{params[:id]}"
    if Integer(params[:id]) > 0 and Integer(params[:id]) <= Integer(most_recent)
        page = Nokogiri::HTML(open(nsURL))

        # this will be exported to JSON
        newSong = Hash.new

        # pre-processing: eliminate <br> tags
        page.search("br").each do |n|
            n.replace("\n")
        end
        
        # extract song details w/ link
        # i.e. category, meter, composer, etc.
        details = Hash.new
        for element in page.css("div#details li") do
            #puts element.css("a").text.empty?
            unless element.css("a").text.empty?
                details[element.css("span.key").text] = [element.css("a").text, element.css("a")[0]["href"]]
            else 
                details[element.css("span.key").text] = nil
            end
        end

        lyrics = Hash.new
        # grab title
        newSong["title"] = page.css("div.post-title span").text.strip()
        for element in page.css("div.lyrics li") do
            # verse numbers are denoted in <li value="1"> tags
            if element["value"]
                # store stanza as a list of lines
                lyrics["stanza " + element["value"]] = element.text.split("\n")

            # chorus(es) are denoted in <li class="chorus"> tags
            elsif element["class"]
                if !lyrics.has_key?(element["class"])
                    lyrics[element["class"]] = element.text.split("\n")
                # if there are multiple choruses:
                else
                    # append some whitespace to create a unique key
                    lyrics[element["class"] + " " + String(1+lyrics.length/2)] = element.text.split("\n")
                end
            end
        end

        # build and return JSON
        newSong["details"] = details
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
get "/children/:id" do
    content_type :json

    #this method is not completely accurate since hymnal.net doesn"t always put the most recent songs on the front page
    #will need to add onto this
    most_recent = 0
    while most_recent == 0
        home = Nokogiri::HTML(open("http://www.hymnal.net/en/home.php"))
        home.search("br").each do |n|
            n.replace("\n")
        end
        for element in home.css("ul.songsublist li") do
            if element.css("span.category").text == "Children"
                num = element.css("a")[0]["href"].gsub(/[^\d]/, "").to_i
                if num > most_recent
                    most_recent = num
                end
            end
        end
    end

    puts most_recent

    childrenURL = "http://hymnal.net/hymn.php/c/#{params[:id]}"
    if Integer(params[:id]) > 0 and Integer(params[:id]) <= Integer(most_recent)
        page = Nokogiri::HTML(open(childrenURL))

        # this will be exported to JSON
        children = Hash.new

        # pre-processing: eliminate <br> tags
        page.search("br").each do |n|
            n.replace("\n")
        end
        
        # extract song details w/ link
        # i.e. category, meter, composer, etc.
        details = Hash.new
        for element in page.css("div#details li") do
            #puts element.css("a").text.empty?
            unless element.css("a").text.empty?
                details[element.css("span.key").text] = [element.css("a").text, element.css("a")[0]["href"]]
            else 
                details[element.css("span.key").text] = nil
            end
        end

        lyrics = Hash.new
        # grab title
        children["title"] = page.css("div.post-title span").text.strip()
        for element in page.css("div.lyrics li") do
            # verse numbers are denoted in <li value="1"> tags
            if element["value"]
                # store stanza as a list of lines
                lyrics["stanza " + element["value"]] = element.text.split("\n")

            # chorus(es) are denoted in <li class="chorus"> tags
            elsif element["class"]
                if !lyrics.has_key?(element["class"])
                    lyrics[element["class"]] = element.text.split("\n")
                # if there are multiple choruses:
                else
                    # append some whitespace to create a unique key
                    lyrics[element["class"] + " " + String(1+lyrics.length/2)] = element.text.split("\n")
                end
            end
        end

        # build and return JSON
        children["details"] = details
        children["lyrics"] = lyrics
        JSON.pretty_generate(children)

    else
        # throw error in JSON
        error = Hash.new
        error["error"] = "Sorry, there is no children's song with that number. The most recent new song known to the API has the number " + most_recent.to_s
        error.to_json
    end

end

# search results
get "/search/:string" do

end

# most recent
get "/most_recent" do
    #grabs most recent children and new song according to home page
    content_type :json

    recent = Hash.new

    recent_ns = 0
    recent_c = 0
    home = Nokogiri::HTML(open("http://www.hymnal.net/en/home.php"))
    home.search("br").each do |n|
        n.replace("\n")
    end
    for element in home.css("ul.songsublist li") do
        if element.css("span.category").text.gsub!(/\P{ASCII}/, "") == "NewSongs"
            num = element.css("a")[0]["href"].gsub(/[^\d]/, "").to_i
            if num > recent_ns
                recent_ns = num
            end
        end
        if element.css("span.category").text == "Children"
            num = element.css("a")[0]["href"].gsub(/[^\d]/, "").to_i
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
