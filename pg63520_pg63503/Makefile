CC     = gcc
SRC    = src/
CFLAGS = -O3 -ffast-math -march=native -fopenmp -g -fno-omit-frame-pointer -Wno-unused-result

.DEFAULT_GOAL = md

md: $(SRC)MD.cpp
	$(CC) $(CFLAGS) $(SRC)MD.cpp -lm -o md

clean:
	rm -f ./md

export OMP_NUM_THREADS ?= 48
run: md
	./md < inputdata.txt
