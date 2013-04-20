#!/bin/sh

FILE_INPUT_PDF="$1"

VERSION="alpha0"

# Initialization of constants
EXIT_BAD_INPUT_FILE="1"		# possible exit codes
EXIT_MISSING_DEPENDENCY="2"
EXIT_INVALID_OUPUT_PDFA="3"
LOG_ERR="0"			# 0=only error messages
LOG_INFO="1"			# 1=error messages and some infos
LOG_DEBUG="2"			# 2=debug level logging

# Initialization the configuration parameters with default values
VERBOSITY="$LOG_ERR"	# default verbosity level
LAN="eng"		# default language of the PDF file (required to get good OCR results)
KEEP_TMP="0"		# do not delete the temporary files (default)
PREPROCESS_DESKEW="1"	# 0=no, 1=yes
PREPROCESS_CLEAN="2"	# 0=no, 
			# 1=clean image to improve OCR, but do not put cleaned image in final PDF 
			# 2=clean image to improve OCR, AND put it in final PDF

# check if the required utilities are installed
echo "Checking if all dependencies are installed"
! command -v gs > /dev/null && echo "Please install ghostcript. Exiting..." && exit $EXIT_MISSING_DEPENDENCY
! command -v identify > /dev/null && echo "Please install ImageMagick. Exiting..." && exit $EXIT_MISSING_DEPENDENCY
! command -v pdfimages > /dev/null && echo "Please install xpdf. Exiting..." && exit $EXIT_MISSING_DEPENDENCY
! command -v pdftoppm > /dev/null && echo "Please install xpdf. Exiting..." && exit $EXIT_MISSING_DEPENDENCY
! command -v pdftk > /dev/null && echo "Please install pdftk. Exiting..." && exit $EXIT_MISSING_DEPENDENCY
! command -v unpaper > /dev/null && echo "Please install unpaper. Exiting..." && exit $EXIT_MISSING_DEPENDENCY
! command -v tesseract > /dev/null && echo "Please install tesseract and tesseract-data. Exiting..." && exit $EXIT_MISSING_DEPENDENCY
! command -v java > /dev/null && echo "Please install java. Exiting..." && exit $EXIT_MISSING_DEPENDENCY



# Initialize path to temporary files
tmp="./tmp"
FILE_SIZE_PAGES="$tmp/page-sizes.txt"		# size in pt of the respective page of the input PDF file
FILES_OCRed_PDFS="${tmp}/*-ocred.pdf"		# string matching all 1 page PDF files that need to be merged
FILE_OUTPUT_PDF="${tmp}/ocred.pdf"		# name of the OCRed PDF file before conversion to PDF/A
FILE_OUTPUT_PDFA="${tmp}/ocred-pdfa.pdf"	# name of the final PDF/A file
FILE_VALIDATION_LOG="${tmp}/pdf_validation.log"	# log file containing the results of the validation of the PDF/A file

# delete tmp files
echo "Removing old temporary files"
rm -r -f "${tmp}"
mkdir -p "${tmp}"




# get the size of each pdf page (width / height) in pt (inch*72)
echo "Input file: Extracting size of each page (in pt)"
identify -format "%w %h\n" "$FILE_INPUT_PDF" > "$FILE_SIZE_PAGES"
sed -I "" '/^$/d' "$FILE_SIZE_PAGES"	# removing empty lines (last one should be)
numpages=`cat "$FILE_SIZE_PAGES" | wc -l | sed 's/^ *//g'`
echo "Input file: The file has $numpages pages"

# Itterate the pages of the input pdf file
cpt="1"
while read pageSize ; do

	# add leading zeros to the page number
	page=`printf "%04d" $cpt`
	echo "Processing page $page"
	
	# create the name of the required file
	curOrigImg="$tmp/${page}_Image"		# original image available in the current PDF page 
						# (the image file may have a different orientation than in the pdf file)
	curHocr="$tmp/$page.hocr"		# hocr file to be generated by the OCR SW for the current page
	curOCRedPDF="$tmp/${page}-ocred.pdf"	# PDF file containing the image + the OCRed text for the current page
	
	echo "Page $page: Computing embedded image resolution"
	# get width / height of PDF page
	heightPDF=`echo $pageSize | cut -f1 -d" "`
	widthPDF=`echo $pageSize | cut -f2 -d" "`
	# extract raw image from pdf file to compute resolution
	# unfortunatelly this image may not be rotated as in the pdf...
	# so we will have to extract it again later
	pdfimages -f $page -l $page -j "$FILE_INPUT_PDF" "$curOrigImg" 1>&2	
	# count number of extracted images
	nbImg=`ls -1 "$curOrigImg"* | wc -l`
	[ $nbImg -ne "1" ] && echo "Not exactly 1 image on page $page. Exiting..." && exit $EXIT_BAD_INPUT_FILE
	
	# Get characteristics of the extracted image
	curOrigImg01=`ls -1 "$curOrigImg"*`
	propCurOrigImg01=`identify -format "%w %h %[colorspace]" "$curOrigImg01"`
	heightCurOrigImg01=`echo "$propCurOrigImg01" | cut -f1 -d" "`
	widthICurOrigImg01=`echo "$propCurOrigImg01" | cut -f2 -d" "`
	colorspaceCurOrigImg01=`echo "$propCurOrigImg01" | cut -f3 -d" "`
	# compute the resolution of the whole page (taking into account all images)
	dpi_x=$(($widthICurOrigImg01*72/$widthPDF))
	dpi_y=$(($heightCurOrigImg01*72/$heightPDF))
	[ "$dpi_x" -ne "$dpi_y" ] && echo "X/Y Resolutions not equal (Not supported currently). Exiting..." && exit $EXIT_BAD_INPUT_FILE
	dpi="$dpi_x"

	# Identify if page image should be saved as ppm (color) or pgm (gray)
	ext="ppm"
	opt=""		
	if [ $colorspaceCurOrigImg01 == "Gray" ]; then
		ext="pgm"
		opt="-gray"
	fi
	curImgPixmap="$tmp/$page.$ext"
	curImgPixmapDeskewed="$tmp/$page.deskewed.$ext"
	curImgPixmapClean="$tmp/$page.cleaned.$ext"
	
	# extract current page as image with right orientation and resoltution
	echo "Page $page: Extracting image as $ext file (${dpi} dpi)"
	pdftoppm -f $page -l $page -r $dpi $opt "$FILE_INPUT_PDF" > "$curImgPixmap"

	# if requested deskew image (without changing its size in pixel)
	if [ "$PREPROCESS_DESKEW" -eq "1" ]; then
		echo "Page $page: Deskewing image"
		convert "$curImgPixmap" -deskew 40% -gravity center -extent ${heightCurOrigImg01}x${widthICurOrigImg01} "$curImgPixmapDeskewed"
	else
		cp "$curImgPixmap" "$curImgPixmapDeskewed"
	fi
	
	# if requested clean image with unpaper to get better OCR results
	if [ "$PREPROCESS_CLEAN" -ge "1" ]; then
		echo "Page $page: Cleaning image with unpaper"
		unpaper --dpi $dpi --mask-scan-size 100 \
			--no-deskew --no-grayfilter --no-blackfilter --no-mask-center --no-border-align \
			"$curImgPixmapDeskewed" "$curImgPixmapClean" 1> /dev/null
	else
		cp "$curImgPixmapDeskewed" "$curImgPixmapClean"
	fi
			
	# perform OCR
	echo "Page $page: Performing OCR"
	tesseract -l "$LAN" "$curImgPixmapClean" "$curHocr" hocr 1> /dev/null 2> /dev/null 
	mv "$curHocr.html" "$curHocr"

	# embed text and image to new pdf file
	echo "Page $page: Embedding text in PDF"
	if [ "$PREPROCESS_CLEAN" -eq "2" ]; then
		image4finalPDF="$curImgPixmapClean"
	else
		image4finalPDF="$curImgPixmapDeskewed"	
	fi
	python hocrTransform.py -r $dpi -i "$image4finalPDF" "$curHocr" "$curOCRedPDF"
	
	# delete temporary files created for the current page
	# to avoid using to much disk space in case of PDF files having many pages
	if [ $KEEP_TMP -eq 0 ]; then
		rm "$curOrigImg"*.*
		rm "$curHocr"
		rm "$curImgPixmap"
		rm "$curImgPixmapDeskewed"
		rm "$curImgPixmapClean"
	fi
	
	# go to next page of the pdf
	cpt=$(($cpt+1))
done < "$FILE_SIZE_PAGES"




# concatenate all pages
echo "Output file: Concatenating all pages"
pdftk $FILES_OCRed_PDFS cat output "$FILE_OUTPUT_PDF"

# insert metadata (copy metadata from input file)
#echo "Output file: Inserting metadata"
# TODO (may work with pdftk update_info)
# the name of the file may be used as title

# convert the pdf file to match PDF/A format
echo "Output file: Conversion to PDF/A" 
gs -dQUIET -dPDFA -dBATCH -dNOPAUSE -dUseCIEColor \
	-sProcessColorModel=DeviceCMYK -sDEVICE=pdfwrite -sPDFACompatibilityPolicy=2 \
	-sOutputFile=$FILE_OUTPUT_PDFA "$FILE_OUTPUT_PDF"

# validate generated pdf file (compliance to PDF/A)
echo "Output file: Checking compliance to PDF/A standard" 
java -jar /root/jhove-1_9/jhove/bin/JhoveApp.jar -m PDF-hul "$FILE_OUTPUT_PDFA" > "$FILE_VALIDATION_LOG"
grep -i "Status|Message" "$FILE_VALIDATION_LOG" # summary of the validation
# check if the validation was successful
pdf_valid=1
grep -i "ErrorMessage" "$FILE_VALIDATION_LOG" && pdf_valid=0
grep -i "Status.*not valid" "$FILE_VALIDATION_LOG" && pdf_valid=0
grep -i "Status.*Not well-formed" "$FILE_VALIDATION_LOG" && pdf_valid=0
[ $pdf_valid -eq 1 ] && echo "Output file: The generated PDF/A file is VALID" \
	|| echo "Output file: The generated PDF/A file is INVALID"




# delete temporary files
if [ $KEEP_TMP -eq 0 ]; then
	rm $FILES_OCRed_PDFS
	rm "$FILE_SIZE_PAGES"
	rm "$FILE_OUTPUT_PDF"
fi

exit 0