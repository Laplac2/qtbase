# qtbase

## Configure and Build with qmake

1. Run the configure script fist(and add the -developer-build option).

    `./configure -prefix=$PWD/qtbase -opensource -confirm-license -nomake tests -nomake examples -dbus -no-separate-debug-info -developer-build`

2. Open QtCreator and go to "Tools > Options > Kits".
3. Go to "Qt Versions" add press "Add" - select the qmake executable generated by the configure script. Then hit "Apply".
4. Go to "Kits" and press "Add" - Make shure to select the correct compilers and debugger and select the previously create "Qt Version". Press "Ok".
5. Open the top level .pro file in QtCreator and choose the previously created Kit. QtCreator will now use the correct qmake executable.

## Configure and Build with cmake

1. Go to [cmake](https://cmake.org/download/).
2. Download source.
3. Do `./bootstrap && make && sudo make install`.

## To Do

* Search `// ### Qt6`.

## Reference

1. [kde build opensource qtbase](https://community.kde.org/Guidelines_and_HOWTOs/Build_from_source/OwnQt5).
2. [how build the qt project itself using qtcreator](https://stackoverflow.com/questions/53163714/how-build-the-qt-project-itself-using-qtcreator).
