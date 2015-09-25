#!/bin/bash

# potd-wikic.sh
# Updates desktop background of Gnome with Wikimedia Commons picture of the day (POTD).
# Downloads images including future ones, adds a descryption caption on bottom, and updates the desktop background.
# Can be run on a server for downloading images then have personal device get them from there thus allowing faster downloads and reduced bandwidth at peak times.

#usage:
# potd-wikic [options] [functions]
# script has both options and functions. Order of the arguments matter. Options must be set before functions.

#functions: can run in any order.
# -g<N>  downloads (full sized) images for N days into the future. 0 downloads just todays. Number is required, no default (for now). Both the webpage and image are stored.
# -c     creates image with caption on bottom.
# -s     sets the desktop image (for Gnome, for now)
# -h     displays help
# -r<N>  removes images older than N days in the past. (needs to be implimented)

#options:
# -d<dir>     working directory (default ~/Pictures/potd-wikic)
# -m<url>     url of mirror.

#typical usage:
#on server: download images to publically accessible directory.
# potd-wikic -w"/var/www/potd-wikic/" -g7

#on personal device: update image then check for new ones.
# potd-wikic -m"http://example.com/potd-wikic/" -c -s -g3

#setup:
#make sure working directory exists. (~/Pictures/potd-wikic by default)
#place in /usr/local/bin as potd-wikic with execute permissions.
#run daily as an anacron job. Unlike cron, anacron runs jobs at the next available oppertunity even if missed such as computer off.
#in Ubuntu, etc/cron.daily is run by anacron. Therefore create script in there containing the command. eg:
#  #!/bin/sh
#  potd-wikic -c -s -g7


#TODO:
#impliment verbosity output
#have disk cleanup of old images. Have remove after so many days old, and/or after reaching disk usage quota.
#really need to have option to get specified thumbnail size to limit bandwidth usage. Some images are huge. Only issue is if one wants to see original picture, or if multiple diplays are used with different resolutions. Should have option for both.
#maybe output the url to the original image the potd.dat, then parse the date from that. That way, one can simply paste that url into browser to get the webpage for the current POTD.
#add more tests, more error handling. ie test if working directory exists.
#options to update other desktops such as KDE, etc
#option to disable caption.
#with the number of options, should probably use a config file.
#allow proxy servers?


#testing:
#offline usage (ensure proper handling of netork errors)
#server usage.
#test various scenarios (try to break script)
#script delay/retry script hasn't been tested.

#ToFix:
#allow arguments which require input to be optional with a default value. eg -g implies -g0. Appears may have to forget using getops (http://stackoverflow.com/questions/14062895/bash-argument-case-for-args-in/14063511#14063511)
#http://commons.wikimedia.org/wiki/Template:Potd/2015-07-27_(en) had problem displaying. Becasue there was no description?

# History
# 2014-11-26: created (Devon Fyson)
# 2015-07-09: Removed "http:" from image url prefix. It now already comes https.

#atomfeed="https://commons.wikimedia.org/w/api.php?action=featuredfeed&feed=potd&feedformat=atom&language=en"
#"http://commons.wikimedia.org/wiki/Template:Potd/2014-11"
#"http://commons.wikimedia.org/wiki/Template:Potd/2014-11-04"
#"http://commons.wikimedia.org/wiki/Template:Potd/2014-11-05_(en)" #with english description.
#use getopts for parsing arguments. http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash

#general user options used by multiple functions.
workingdir="$HOME/Pictures/potd-wikic/" #working directory for wallpapers.
errorFile="errors.log"
imageFileCurrent="potd.jpg"
lastUpdateFile="potd.dat"
webpageFile="potd.html"
verbose="0"

#getImages options:
delay="0" #minutes delay before getting images. Useful for wireless connections which are slow to establish.
repeatDelays=("10" "20" "30") #minutes of delay between re-tries before giving up.
f="0" #number of webpages in the future to download (0 = only todays)
baseurl="http://commons.wikimedia.org/wiki/Template:Potd/" #base URL (prefix) for wikimedia POTD.
lang="_(en)"	# suffix for url specifying language for caption.

#createImage options:
imageFileCurrentDescription="description.png"
resX="1280" #display resolution (x)
resY="1024" #display resolution (y)
textSize="13" #text size in points for caption.

#cleanupImages options
quota="100" #maximum space quota in MB
h="7" #days in past after which to delete images.

if [[ -d "$workingdir" ]]; then
	cd $workingdir
fi

#internal variables.
repeatIndex=0

function getImages() { 

	#get the webpages and images including in future.
	#Decided to go with downloading and storing whole webpage and parse it as needed as apposed to storing parsed information. Will be easier to debug, and users can download pages and images using other methods.
	echo "delaying for $delay min"
	sleep "$delay""m"
	echo -n "testing connection..."
 	if [[ $(ping -q -w 1 -c 1 `ip r | grep default | cut -d ' ' -f 3` > /dev/null && echo ok || echo "") ]]; then
		echo " ok."
		echo "getting images..." #if [ "$verbose" == "1" ]; then echo "getting images..."; fi
		for i in $(seq 0 $f);
		do
			date=`date +%F --date="+$i days"` #dates $i days in future.
			echo "$date (+$i days): $baseurl$date$lang"
			webpageFile="$date.html" #file to download webpage to (must be unique name for each day)
			imageFile="$date.jpg" #file to download image to (must be unique name for each day)
			if [[ ! -f "$imageFile" ]] || [ ! -f "$webpageFile" ]; then #download image is either or both files don't exist (since $webpageFile is written last, if it doesn't exist then likely download didn't complete.
				if [[ $mirrorUrl ]]; then
					echo -n "  webpage: trying mirror... "
					webpage=`wget --waitretry=20 --tries=20 --quiet "$mirrorUrl$webpageFile" -qO-` #download webpage from mirror.

					if [[ $? -eq "0" ]]; then #first ensure wget didn't return any errors.
						mirrorWebpageSuccess=`echo "$webpage" | perl -ne "if(m/<title>Template:Potd\/$date \(en\) - Wikimedia Commons<\/title>/){print 1}"` #test to see if got good page.
						if [[ $mirrorWebpageSuccess ]]; then #then check if file contents is really what we want.
							echo "ok."
						else
							echo -e "\e[1;31mfailed\e[0m. Wrong webpage. Dumping to failed.html"
							echo "$webpage" > "failed.html"
							echo `date "+%F %T"`": wrong webpage. $mirrorUrl$webpageFile" >> $errorFile
						fi
					else
						echo -e "\e[1;31mfailed\e[0m. wget error $?. $mirrorUrl$webpageFile"
						echo `date "+%F %T"`": wget error $?. $mirrorUrl$webpageFile" >> $errorFile
					fi
				fi

				if [[ ! $mirrorWebpageSuccess ]]; then #if mirror didn't work, try downloading from wikimedia.
					echo -n "  webpage: trying Wikimedia... "
					webpage=`wget --waitretry=20 --tries=20 --quiet "$baseurl$date$lang" -qO-` #download webpage to variable

					if [[ $? -eq "0" ]]; then #first ensure wget didn't return any errors.
						webpageSuccess=`echo "$webpage" | perl -ne "if(m/<title>Template:Potd\/$date \(en\) - Wikimedia Commons<\/title>/){print 1}"` #test to see if got good page.
						if [[ $webpageSuccess ]]; then #then check if file contents is really what we want.
							echo "ok."
						else
							echo -e "\e[1;31mfailed\e[0m. Wrong webpage. Dumping to failed.html"
							echo "$webpage" > "failed.html"
							echo `date "+%F %T"`": wrong webpage. $baseurl$date$lang" >> $errorFile
						fi
					else
						echo -e "\e[1;31mfailed\e[0m. wget error $?"
						echo `date "+%F %T"`": wget error $?. $baseurl$date$lang" >> $errorFile
					fi
				fi

				thumbnailUrl=`echo $webpage | grep '<div class="thumbinner"' | perl -pe 's/.*(<div class=\"thumbinner\".*?<\/span>).*/\1/' | perl -pe 's/.*?src="(.*?)".*/\1/'` #thumbnail image url. Need either grep or first perl depending if webpage is saved to file or kept in variable (variable has no newlines)
				original=`echo $thumbnailUrl | perl -pe 's/\/thumb\//\//' | perl -pe 's/(.*)\/.*/\1/'` #derive original image url from thumnail image url

				if [[ $mirrorUrl && ($mirrorWebpageSuccess || $webpageSuccess) ]]; then #try downloading image from mirror if either webpage was successful. Alternatively download from mirror only if webpage was successful.
					echo -n "  image: trying mirror... "
					wget --waitretry=20 --tries=20 --continue --quiet "$mirrorUrl$imageFile" -O$imageFile #get the picture.

					if [[ $? -eq "0" ]]; then #first ensure wget didn't return any errors.
						echo "ok."
						mirrorImageSuccess="1"
					else
						echo -e "\e[1;31mfailed\e[0m. wget error $?"
						echo `date "+%F %T"`": wget error $?. $mirrorUrl$imageFile" >> $errorFile
					fi
				fi
				if [[ ! $mirrorImageSuccess ]]; then #try wikimedia (if either mirror was never tried nor successful)
					echo -n "  image: trying Wikimedia... "
					wget --waitretry=20 --tries=20 --continue --quiet "$original" -O$imageFile #get the picture.

					if [[ $? -eq "0" ]]; then #first ensure wget didn't return any errors.
						echo "ok."
						imageSuccess="1"
					else
						echo -e "\e[1;31mfailed\e[0m. wget error $?"
						echo `date "+%F %T"`": wget error $?. $original" >> $errorFile
					fi
				fi
			else
				echo "  both files already exists. Skipping download."
			fi

			if [[ $webpageSuccess || $mirrorWebpageSuccess ]] && [[ $imageSuccess || $mirrorImageSuccess ]]; then #if successfully got both webpage and image, then print webpage to file.
				echo -e $webpage > $webpageFile #write the webpage to the file last after both previous files downloaded (incase script is intrupted, it will re-download it).
				webpageSuccess=""
				mirrorWebpageSuccess=""
				imageSuccess=""
				mirrorImageSuccess=""
			fi
		done
	else
		#repeat as per $repeatDelays array.
		if [[ $repeatIndex -le ${#repeatDelays[@]} ]]; then #check how many times we have already tried.
			echo "failed. Retrying in $repeatDelays[$repeatIndex] minutes."
			(($delayIndex++))
			sleep "${repeatDelays[$repeatIndex]}""m"
			getImages
		else
			echo -e "\e[1;31mfailed\e[0m."
		fi
	fi
}


function createPOTD() {
	#update todays POTD
	echo -n "creating POTD... "
	date=`date +%F`
	lastUpdate=`cat $lastUpdateFile` #check last update. If already updated then die.
	if [ "$lastUpdate" == "$date" ]; then
		echo -e " wallpaper already updated $date."
	else
		webpageFile="$date.html"
		imageFile="$date.jpg"
		x=`cat "$webpageFile" | grep '<div class="thumbinner"'` #useful chunk.
		width=`echo $x | perl -pe 's/.*?data-file-width="(.*?)".*/\1/'` #pull out width and height of original image.
		height=`echo $x | perl -pe 's/.*?data-file-height="(.*?)".*/\1/'`
		description=`cat "$webpageFile" | grep '<span lang="en" class="description en"' | head -n1 | perl -pe 's/.*description en">(.*?)<\/span>.*/\1/'` #get description
		descriptionPlain=`echo $description | perl -pe 's/<.*?>//g'` #remove html links (turn into plaintext description)
		#add text:
		imageAR=$(printf %.$2f $(echo "scale=3; $width / $height * 1000" | bc)) #aspect ratio.
		screenAR=$(printf %.$2f $(echo "scale=3; $resX / $resY * 1000" | bc))
		if [[ $imageAR -gt $screenAR ]]; then #scale based on comparing aspect ratios.
			ps=$(printf %.$2f $(echo "scale=3; $textSize * ($height / ($resX / $width * $height))  " | bc)) #need to calculate $resY knowing the scaling factor in x direction and height of image. (ie is a substitution for $resY = $resX / $width * $height)
		else
			ps=$(printf %.$2f $(echo "scale=3; $textSize * ($height / $resY)" | bc)) #simple scaling compared to x direction.
		fi
		convert -background black -pointsize $ps -size $width -fill white caption:"$descriptionPlain" $imageFileCurrentDescription #turn description text into image. #-gravity center for center justified.
		convert $imageFile $imageFileCurrentDescription -background black -append $imageFileCurrent #append inmages together.
		#set the desktop image.

		#write date to file for checking if run again.
		echo $date > $lastUpdateFile
		echo "ok."
	fi
}

function setPOTD() { 
	echo -n "setting POTD... "
	gsettings set org.gnome.desktop.background picture-uri "file://$workingdir/$imageFileCurrent"
	echo "ok."
}

function cleanupImages() { #delete
	echo "cleanup images..."
	#TODO impliment
}

function show_help() {
echo '    :: potd-wikic ::
 Updates desktop background of Gnome with Wikimedia Commons picture of the day (POTD).
Downloads images including future ones, adds a descryption caption on bottom, and updates the desktop background.
Can be run on a server for downloading images then have personal device get them from there thus allowing faster downloads and reduced bandwidth at peak times.

usage:
 potd-wikic [options] [functions]
 script has both options and functions. Order of the arguments matter. Options must be set before functions.

functions: can run in any order.
 -g<N>  downloads (full sized) images for N days into the future. 0 downloads just todays. Number is required, no default (for now). Both the webpage and image are stored.
 -c     creates image with caption on bottom.
 -s     sets the desktop image (for Gnome, for now)
 -h     displays help
 -r<N>  removes images older than N days in the past. (needs to be implimented)

options:
 -d<dir>     working directory (default ~/Pictures/potd-wikic/)
 -m<url>     url of mirror.

typical usage:
  on server: download images to publically accessible directory.
    potd-wikic -w"/var/www/potd-wikic/" -g7
  on personal device: update image then check for new ones.
    potd-wikic -m"http://example.com/potd-wikic/" -c -s -g3

setup:
 make sure working directory exists. (~/Pictures/potd-wikic by default)
place in /usr/local/bin as potd-wikic with execute permissions.
run daily as an anacron job. Unlike cron, anacron runs jobs at the next available oppertunity even if missed such as computer off.
in Ubuntu, etc/cron.daily is run by anacron. Therefore create script in there containing the command. eg:
  #!/bin/sh
  potd-wikic -c -s -g7
'


}

OPTIND=1 #POSIX variable. Reset in case getopts has been used previously in the shell.

while getopts "vh?g:csm:d:r:" opt; do #include list of varibles used. Add : after ones which require inpu
	case "$opt" in
	h|\?)
		show_help
		exit 0
		;;
	v) #increase verbosity
		verbose="1"
		;;
	g)
		f=$OPTARG
		getImages
		;;
	c)
		createPOTD
		;;
	s)
		setPOTD
		;;
	r)
		h=$OPTARG
		cleanupImages
		;;
	m)
		mirrorUrl=$OPTARG
		;;
	d)
		workingdir=$OPTARG

		if [[ -d "$workingdir" ]]; then
			cd $workingdir
		else
			echo "specified working directory '$workingdir' doesn't exist."
			exit
		fi
		cd $workingdir
		;;

	esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift
