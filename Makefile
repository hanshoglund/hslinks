
# HSLINKS=hslinks
HSLINKS=dist/build/hslinks/hslinks
CABAL_FILES=\
	../music-score/music-score.cabal

test:
	$(HSLINKS) $(CABAL_FILES) <Test.md