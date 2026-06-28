import bigscreen_jukebox


def test_package_has_version():
    assert isinstance(bigscreen_jukebox.__version__, str)
    assert bigscreen_jukebox.__version__
