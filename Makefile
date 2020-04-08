execname=mectool

all:
	g++ -O2 -o $(execname) *.cpp -lnuma

