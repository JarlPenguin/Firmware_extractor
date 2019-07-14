#/bin/bash

# Supported Firmwares:
# Aonly OTA
# Raw image
# tarmd5
# chunk image
# QFIL
# AB OTA
# Image zip

usage() {
	echo "Usage: $0 <Path to firmware> [Output Dir]"
	echo -e "\tPath to firmware: the zip!"
	echo -e "\tOutput Dir: the output dir!"
}

if [ "$1" == "" ]; then
	echo "BRUH: Enter all needed parameters"
	usage
	exit 1
fi

LOCALDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOST="$(uname)"
toolsdir="$LOCALDIR/tools"
simg2img="$toolsdir/$HOST/bin/simg2img"
packsparseimg="$toolsdir/$HOST/bin/packsparseimg"
payload_extractor="$toolsdir/update_payload_extractor/extract.py"
sdat2img="$toolsdir/sdat2img.py"

romzip="$(realpath $1)"
PARTITIONS="system vendor cust odm oem modem dtbo boot"
EXT4PARTITIONS="system vendor cust odm oem"

if [[ ! $(7z l $romzip | grep ".*system.ext4.tar.*\|.*.tar\|.*chunk\|system\/build.prop\|system.new.dat\|system_new.img\|system.img\|payload.bin\|image.*.zip\|.*system_.*" | grep -v ".*chunk.*\.so$") ]]; then
	echo "BRUH: This type of firmwares not supported"
	exit 1
fi

echo "Create Temp and out dir"
outdir="$LOCALDIR/out"
if [ ! "$2" == "" ]; then
    outdir="$(realpath $2)"
fi
tmpdir="$outdir/tmp"
mkdir -p "$tmpdir"
mkdir -p "$outdir"

echo "Extracting firmware on: $outdir"
cd $tmpdir

if [[ $(7z l $romzip | grep NON-HLOS) ]]; then
    echo "NON-HLOS modem detected"
    7z e $romzip NON-HLOS.bin */NON-HLOS.bin 2>/dev/null >> $tmpdir/zip.log
    mv NON-HLOS.bin modem.img
    $simg2img modem.img "$outdir"/modem.img 2>/dev/null
    if [[ ! -s "$outdir"/modem.img ]] && [ -f modem.img ]; then
        mv modem.img "$outdir"/modem.img
    fi
fi

if [[ $(7z l $romzip | grep system.new.dat) ]]; then
	echo "Aonly OTA detected"
	for partition in $PARTITIONS; do
		7z e $romzip $partition.new.dat* $partition.transfer.list $partition.img 2>/dev/null >> $tmpdir/zip.log
		cat $partition.new.dat.{0..999} 2>/dev/null >> $partition.new.dat
		cat $partition.new.dat.br.{0..999} 2>/dev/null >> $partition.new.dat
		rm -rf $partition.new.dat.{0..999} $partition.new.dat.br.{0..999}
	    ls | grep "\.new\.dat" | while read i; do
		    line=$(echo "$i" | cut -d"." -f1)
		    if [[ $(echo "$i" | grep "\.dat\.xz") ]]; then
			    7z e "$i" 2>/dev/null >> $tmpdir/zip.log
			    rm -rf "$i"
		    fi
		    if [[ $(echo "$i" | grep "\.dat\.br") ]]; then
			    echo "Converting brotli $partition dat to normal"
			    brotli -d "$i"
			    rm -f "$i"
		    fi
		    echo "Extracting $partition"
		    python3 $sdat2img $line.transfer.list $line.new.dat "$outdir"/$line.img > $tmpdir/extract.log
		    rm -rf $line.transfer.list $line.new.dat
	    done
    done
elif [[ $(7z l $romzip | grep "system_new.img\|system.img$") ]]; then
	echo "Image detected"
	for partition in $PARTITIONS; do
		7z e $romzip $partition_new.img $partition.img */$partition.img */$partition_new.img 2>/dev/null >> $tmpdir/zip.log
		if [[ -f $partition_new.img ]]; then
			mv $partition_new.img $partition.img
		fi
	done
	romzip=""
elif [[ $(7z l $romzip | grep .tar) && ! $(7z l $romzip | grep tar.md5 | gawk '{ print $6 }' | grep AP_) ]]; then
	tar=$(7z l $romzip | grep .tar | gawk '{ print $6 }')
	echo "non AP tar detected"
	7z e $romzip $tar 2>/dev/null >> $tmpdir/zip.log
	echo "Extracting images..."
	for partition in $PARTITIONS; do
        7z e $tar $partition.img.ext4 $partition.img */$partition.img 2>/dev/null >> $tmpdir/zip.log
		if [[ -f $partition.img.ext4 ]]; then
			mv $partition.img.ext4 $partition.img
		fi
	done
    rm -rf $tar
elif [[ $(7z l $romzip | grep tar.md5 | gawk '{ print $6 }' | grep AP_) ]]; then
	echo "AP tarmd5 detected"
	mainmd5=$(7z l $romzip | grep tar.md5 | gawk '{ print $6 }' | grep AP_)
	cscmd5=$(7z l $romzip | grep tar.md5 | gawk '{ print $6 }' | grep CSC_)
	echo "Extracting tarmd5"
	7z e $romzip $mainmd5 $cscmd5 2>/dev/null >> $tmpdir/zip.log
	mainmd5=$(7z l $romzip | grep tar.md5 | gawk '{ print $6 }' | grep AP_ | rev | cut -d "/" -f 1 | rev)
	cscmd5=$(7z l $romzip | grep tar.md5 | gawk '{ print $6 }' | grep CSC_ | rev | cut -d "/" -f 1 | rev)
	echo "Extracting images..."
	for i in "$mainmd5" "$cscmd5"; do
		for partition in $PARTITIONS; do
			tarulist=$(tar -tf $i | grep -e ".*$partition.*\.img.*\|.*$partition.*ext4")
			echo "$tarulist" | while read line; do
				tar -xf "$i" "$line"
				if [[ $(echo "$line" | grep "\.lz4") ]]; then
					lz4 "$line"
					rm -f "$line"
					line=$(echo "$line" | sed 's/\.lz4$//')
				fi
				if [[ $(echo "$line" | grep "\.ext4") ]]; then
					mv "$line" "$(echo "$line" | cut -d'.' -f1).img"
				fi
			done
		done
	done
	if [[ -f system.img ]]; then
		rm -rf $mainmd5
		rm -rf $cscmd5
	else
		echo "Extract failed"
        rm -rf "$tmpdir"
		exit 1
	fi
	romzip=""
elif [[ $(7z l $romzip | grep chunk | grep -v ".*\.so$") ]]; then
	echo "chunk detected"
	for partition in $PARTITIONS; do
		7z e $romzip *$partition*chunk* */*$partition*chunk* $partition.img */$partition.img 2>/dev/null >> $tmpdir/zip.log
		rm -f *"$partition"_b*
		romchunk=$(ls | grep chunk | grep $partition | sort)
		if [[ $(echo "$romchunk" | grep "sparsechunk") ]]; then
			$simg2img $(echo "$romchunk" | tr '\n' ' ') $partition.img.raw 2>/dev/null
			rm -rf *$partition*chunk*
			if [[ -f $partition.img ]]; then
				rm -rf $partition.img.raw
			else
				mv $partition.img.raw $partition.img
			fi
		fi
	done
elif [[ $(7z l $romzip | grep rawprogram) ]]; then
	echo "QFIL detected"
	rawprograms=$(7z l $romzip | gawk '{ print $6 }' | grep rawprogram)
	7z e $romzip $rawprograms 2>/dev/null >> $tmpdir/zip.log
	for partition in $PARTITIONS; do
		partitionsonzip=$(7z l $romzip | gawk '{ print $6 }' | grep $partition)
        if [[ ! $partitionsonzip == "" ]]; then
		    7z e $romzip $partitionsonzip 2>/dev/null >> $tmpdir/zip.log
            if [[ ! -f "$partition.img" ]]; then
		        rawprogramsfile=$(grep -rlw $partition rawprogram*)
		        $packsparseimg -t $partition -x $rawprogramsfile > $tmpdir/extract.log
		        mv "$partition.raw" "$partition.img"
            fi
        fi
	done
elif [[ $(7z l $romzip | grep payload.bin) ]]; then
	echo "AB OTA detected"
	7z e $romzip payload.bin 2>/dev/null >> $tmpdir/zip.log
	for partition in $PARTITIONS; do
		python $payload_extractor payload.bin --partitions $partition --output_dir $tmpdir > $tmpdir/extract.log
		if [[ -f "$tmpdir/$partition" ]]; then
			mv "$tmpdir/$partition" "$outdir/$partition.img"
		fi
	done
	rm payload.bin
    rm -rf "$tmpdir"
	exit
elif [[ $(7z l $romzip | grep "image.*.zip") ]]; then
	echo "Image zip firmware detected"
	thezip=$(7z l $romzip | grep "image.*.zip" | gawk '{ print $6 }')
	7z e $romzip $thezip 2>/dev/null >> $tmpdir/zip.log
	thezipfile=$(echo $thezip | rev | cut -d "/" -f 1 | rev)
	mv $thezipfile temp.zip
	"$LOCALDIR/extractor.sh" temp.zip "$outdir"
	exit
fi

for partition in $PARTITIONS; do
    if [ -f $partition.img ]; then
	    $simg2img $partition.img "$outdir"/$partition.img 2>/dev/null
    fi
	if [[ ! -s "$outdir"/$partition.img ]] && [ -f $partition.img ]; then
		mv $partition.img "$outdir"/$partition.img
	fi

	if [[ $EXT4PARTITIONS =~ (^|[[:space:]])"$partition"($|[[:space:]]) ]] && [ -f "$outdir"/$partition.img ]; then
		offset=$(LANG=C grep -aobP -m1 '\x53\xEF' "$outdir"/$partition.img | head -1 | gawk '{print $1 - 1080}')
        if [[ "$offset" == 128055 ]]; then
            offset=131072
        fi
		if [ ! $offset == "0" ]; then
			echo "Header detected on $partition"
			dd if="$outdir"/$partition.img of="$outdir"/$partition.img-2 ibs=$offset skip=1 2>/dev/null
			mv "$outdir"/$partition.img-2 "$outdir"/$partition.img
		fi
	fi

	if [ ! -s "$outdir"/$partition.img ] && [ -f "$outdir"/$partition.img ]; then
		rm "$outdir"/$partition.img
	fi
done

cd "$LOCALDIR"
rm -rf "$tmpdir"
