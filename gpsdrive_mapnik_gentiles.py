#!/usr/bin/python
"""GpsDrive Generate Mapnik Tiles

Generates 1280x1024 Mapniktiles for GpsDrive

Usage: python gpsdrive_mapnik_gentiles.py [options]

Options:
  -h, --help     show this help
  -b, --bbox     boundingbox (minlon,minlat,maxlon,maxlat)
                  - Be carefull! "Quote" negative values!
  -s, --scale    scale single/range (zoom level or min-max)
                   (below "9" Mercator becomes distorted;
                    actual scale will vary with latitude)
                        9 - 1:600,000
                       10 - 1:300,000
                       11 - 1:150,000
                       12 - 1:75,000
                       13 - 1:40,000
                       14 - 1:20,000
                       15 - 1:10,000
                       16 - 1:5,000
                       17 - 1:2,500
  -j, --jpeg     save tiles as JPEG instead of PNG
  -n, --dry-run  don't actually write anything to disk
  --test         testrun = generates Munich example
                             
Examples:
  
  Munich:
    gpsdrive_mapnik_gentiles.py -b  11.4,48.07,11.7,48.2 -s 10-16
  
  World: (just to demonstrate lat/lon order; scale not recommended)
    gpsdrive_mapnik_gentiles.py -b "-180.0,-90.0,180.0,90.0" -s 1-6
"""

from math import pi,cos,sin,log,exp,atan
from subprocess import call
import sys, os
import getopt
import string


DEG_TO_RAD = pi/180
RAD_TO_DEG = 180/pi

def calc_scale (lat, zoom):
    # GpsDrive's hardcoded pixels per meter ratio
    PixelFact = 2817.947378
    # wgs84 major Earth axis
    a = 6378137.0
    dynscale = ( a * 2*pi * cos(lat * DEG_TO_RAD) * PixelFact ) / ( 256*pow(2,zoom) )
    #print "Scale: %.1f" % dynscale
    return dynscale

def minmax (a,b,c):
    a = max(a,b)
    a = min(a,c)
    return a

class GoogleProjection:
    def __init__(self,levels=18):
        self.Bc = []
        self.Cc = []
        self.zc = []
        self.Ac = []
        c = 256
        for d in range(0,levels):
            e = c/2;
            self.Bc.append(c/360.0)
            self.Cc.append(c/(2 * pi))
            self.zc.append((e,e))
            self.Ac.append(c)
            c *= 2
                
    def fromLLtoPixel(self,ll,zoom):
         d = self.zc[zoom]
         e = round(d[0] + ll[0] * self.Bc[zoom])
         f = minmax(sin(DEG_TO_RAD * ll[1]),-0.9999,0.9999)
         g = round(d[1] + 0.5*log((1+f)/(1-f))*-self.Cc[zoom])
         return (e,g)
     
    def fromPixelToLL(self,px,zoom):
         e = self.zc[zoom]
         f = (px[0] - e[0])/self.Bc[zoom]
         g = (px[1] - e[1])/-self.Cc[zoom]
         h = RAD_TO_DEG * ( 2 * atan(exp(g)) - 0.5 * pi)
         return (f,h)


import os
from PIL.Image import fromstring, new
from PIL.ImageDraw import Draw
from StringIO import StringIO
from mapnik import *

def render_tiles(bbox, mapfile, tile_dir, mapkoordfile, write_to_disk,
                 minZoom=1,maxZoom=18, img_ext='', name="unknown"):

    print "Render_tiles(", bbox, "\n             ", \
          mapfile, " ", tile_dir, "\n             ", \
          "minZoom=%d" % minZoom, "maxZoom=%d" % maxZoom, name, img_ext, ")"

    if write_to_disk:
        fh_mapkoord = open(mapkoordfile, "a") 
        if fh_mapkoord == 0:
            sys.exit("Can not open map_koord.txt.")

        if not os.path.isdir(tile_dir):
             os.mkdir(tile_dir)
    else:
        fh_mapkoord = open(mapkoordfile, "r") 
        if fh_mapkoord == 0:
            sys.exit("Can not open map_koord.txt.")

    gprj = GoogleProjection(maxZoom+1) 

    #m = Map(2 * 256,2 * 256)
    m = Map(1280,1024)
    load_map(m,mapfile)

    #prj = Projection("+proj=merc +datum=WGS84")
    # What follows is from /usr/share/proj/esri.extra, EPSG:900913
    #  "Chris' funny epsgish code for the google mercator"
    prj = Projection("+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs")

    ll0 = (bbox[0],bbox[3])
    ll1 = (bbox[2],bbox[1])

    for z in range(minZoom,maxZoom + 1):
        if z == 9:
            print "CAUTION: Mercator projection begins to be noticeably distorted at this zoom level."
        elif z < 9:
            print "WARNING: Mercator projection is very distorted at this zoom level."

        px0 = gprj.fromLLtoPixel(ll0,z)
        px1 = gprj.fromLLtoPixel(ll1,z)

        for x in range(int(px0[0]/640.0),int(px1[0]/640.0)+1):
            for y in range(int(px0[1]/512.0),int(px1[1]/512.0)+1):
                p0 = gprj.fromPixelToLL((x * 640.0, (y+1) * 512.0),z)
                p1 = gprj.fromPixelToLL(((x+1) * 640.0, y * 512.0),z)

                actual_scale = calc_scale( (p0[1] + p1[1])/2, z)

                # render a new tile and store it on filesystem
                c0 = prj.forward(Coord(p0[0],p0[1]))
                c1 = prj.forward(Coord(p1[0],p1[1]))
            
                bbox = Envelope(c0.x,c0.y,c1.x,c1.y)
                bbox.width(bbox.width() * 2)
                bbox.height(bbox.height() * 2)
                m.zoom_to_box(bbox)
                
                # check if we have directories in place
                zoom = "%s" % z
                str_x = "%s" % x
                str_y = "%s" % y

                if write_to_disk:
                    if not os.path.isdir(tile_dir + zoom):
                        os.mkdir(tile_dir + zoom)
                    if not os.path.isdir(tile_dir + zoom + '/' + str_x):
                        os.mkdir(tile_dir + zoom + '/' + str_x)

                tile_uri = tile_dir + zoom + '/' + str_x + '/' + str_y + img_ext
                tile_path = "mapnik/" + zoom + '/' + str_x + '/' + str_y + img_ext

                exists= ''
                if os.path.isfile(tile_uri):
                    exists= " [exists]"
                    empty= ''
                    bytes = os.stat(tile_uri)[6]
                    # FIXME: I don't thing this bytes test actually works...
                    if bytes == 137:
                        empty = "Empty Tile"

                else:
                    im = Image(1280, 1024)
                    render(m, im)
                    im = fromstring('RGBA', (1280, 1024),
                                    im.tostring()).convert("RGB")
                    #im = im.crop((128,128,512-128,512-127))
                    if write_to_disk:
                        fh = open(tile_uri,'w+b')
                        if img_ext == '.png':
                            im.save(fh, 'PNG', optimize=True)
                        else:
                            im.save(fh, 'JPEG', quality=85)
                        # 'convert' is a program from the Imagemagick package
                        command = "convert -type optimize %s %s" % (tile_uri,tile_uri)
                        call(command, shell=True)

                        fh_mapkoord.write(tile_path + " ")
                        fh_mapkoord.write(str((p0[1] + p1[1]) / 2) + " ")
                        fh_mapkoord.write(str((p0[0] + p1[0]) / 2) + " ")
                        fh_mapkoord.write(str(actual_scale))
                        fh_mapkoord.write(" " + str(p0[1]) + " " + str(p0[0]))
                        fh_mapkoord.write(" " + str(p1[1]) + " " + str(p1[0]))
                        fh_mapkoord.write("\n")

                        bytes = os.stat(tile_uri)[6]
                        empty= "[created]"
                        if bytes == 137:
                            empty = "Empty Tile"
                    else:
                        empty = "[simulation]"

                print name, "[%d-%d]: " % (minZoom,maxZoom), \
                     "zoom:%2d " % z, "scale=1:%.1f " % actual_scale, \
                     "x:%5d " % x, "y:%5d " % y, \
                     " p:(%.7f, %.7f)/(%.7f, %.7f)" % (p0[0],p0[1],p1[0],p1[1]), \
                     exists, empty

    fh_mapkoord.close()


    
def usage():
    print __doc__


def main(argv):

    home = os.environ['HOME']
    user = os.environ['USER']
    data = home + "/.gpsdrive"
    mapfile = data + "/osm.xml"
    tile_dir = home + "/.gpsdrive/maps/mapnik/"
    mapkoordfile = home + "/.gpsdrive/maps/map_koord.txt"

    minZoom = 0
    maxZoom = 0
    bboxset = 0
    img_ext = '.png'
    write_to_disk = True

    try:
        opts, args = getopt.getopt(argv, "hb:s:jn",
                                   ["help", "bbox=", "scale=", "test",
                                   "jpeg", "dry-run"])
    except getopt.GetoptError:
        sys.exit("Invalid option!")
    
    for opt, arg in opts:
        if opt in ("-h", "--help"):
            usage()
            sys.exit()
        elif opt in ("-b", "--bbox"):
            bboxset = 1
            bboxs = string.split(arg, ',')
        elif opt in ("-s" , "--scale"):
            zooms = string.split(arg, '-')
            if len(zooms) == 2:
                minZoom = eval(zooms[0])
                if str(minZoom) <> zooms[0]: minZoom = 0
                maxZoom = eval(zooms[1])
                if str(maxZoom) <> zooms[1]: maxZoom = 0
            elif len(zooms) == 1:
                minZoom = eval(zooms[0])
                if str(minZoom) <> zooms[0]: minZoom = 0
                maxZoom = minZoom

        elif opt in ("--test"):
            bbox = (11.4,48.07,11.7,48.2)
            minZoom = 10
            maxZoom = 16
            render_tiles(bbox, mapfile, tile_dir, minZoom, maxZoom, "Test")
            sys.exit()
        elif opt in ("-j", "--jpeg"):
            img_ext = '.jpg'
        elif opt in ("-n", "--dry-run"):
            write_to_disk = False

    if not os.path.isfile(mapfile):
        command = "sed 's,\@DATA_DIR\@,/mapnik,g;s,\@USER\@," + user + ",g;' </mapnik/osm.xml >" + mapfile
        print "Creating " + mapfile
        print "Command " + command
        if write_to_disk:
            call(command, shell=True)

    if bboxset == 0:
       sys.exit("No boundingbox set!")
            
    if len(bboxs) < 4:
        sys.exit("Boundingbox invalid!")
    
    # check for correct values
    if str(eval(bboxs[0])) != bboxs[0] or \
       str(eval(bboxs[1])) != bboxs[1] or \
       str(eval(bboxs[2])) != bboxs[2] or \
       str(eval(bboxs[3])) != bboxs[3]:
        # rounding problems... what exactly is this supposed to be checking ???
        sys.exit("Boundingbox invalid!")
        
    if minZoom < 1 or minZoom > 17 or \
       maxZoom < 1 and maxZoom > 17 or \
       minZoom > maxZoom or \
       int(minZoom) <> minZoom or \
       int(maxZoom) <> maxZoom:
        sys.exit("Invalid scale!")
        
    #ok transform bboxs to a bbox with float
    bbox = (eval(bboxs[0]), eval(bboxs[1]), eval(bboxs[2]), eval(bboxs[3]))
    
    #start rendering
    render_tiles(bbox, mapfile, tile_dir, mapkoordfile, write_to_disk,
                 minZoom, maxZoom, img_ext, "Generate:")
    
    #return info
    print "\n", "Finished.\n"


if __name__ == "__main__":
    main(sys.argv[1:])
