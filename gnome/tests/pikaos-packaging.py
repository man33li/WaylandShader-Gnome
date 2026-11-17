#!/usr/bin/env python3
"""Check PikaOS install rules with dummy artifacts, without building/loading native code."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

APP = Path(__file__).resolve().parents[2]


class PikaOSPackaging(unittest.TestCase):
    def test_target_and_readme(self):
        metadata = json.loads((APP / "gnome/extension/metadata.json").read_text())
        self.assertEqual(metadata["shell-version"], ["51"])
        root = (APP / "CMakeLists.txt").read_text()
        self.assertIn("set(WAYLANDSHADER_EXPERIMENTAL_GNOME51 ON)", root)
        self.assertIn("add_subdirectory(gnome)", root)
        readme = (APP / "README.md").read_text()
        for block in re.findall(r"```sh\n(.*?)```", readme, re.S):
            subprocess.run(["bash", "-n"], input=block, text=True, check=True)
        for link in re.findall(r"\]\(([^)]+)\)", readme):
            if "://" not in link and not link.startswith("#"):
                self.assertTrue((APP / link.split("#")[0]).exists(), link)

    def test_production_install_rules_with_dummy_artifacts(self):
        """Exercise the actual install/schema tail, not an alternative installer."""
        cmake = (APP / "gnome/CMakeLists.txt").read_text()
        install_rules = cmake[cmake.index('set(EXTENSION_UUID "'):]
        with tempfile.TemporaryDirectory(prefix="pikaos-packaging-") as temporary:
            root = Path(temporary)
            source, build = root / "source", root / "build"
            source.mkdir()
            build.mkdir()
            shutil.copytree(APP / "gnome/extension", source / "extension")
            shutil.copy2(APP / "gnome/org.waylandshader.GnomeController.desktop", source)
            private = root / "private.so.2"
            private.write_bytes(b"dummy private DSO; never loaded\n")
            link = root / "private.so"
            link.symlink_to(private.name)
            for name in ["libwaylandshader-gnome.so", "WaylandShader-1.0.gir",
                         "WaylandShader-1.0.typelib", "waylandshader-gnomectl",
                         "waylandshader-gnome-controller"]:
                (build / name).write_text("dummy build artifact; never executed\n")
            (source / "CMakeLists.txt").write_text('''cmake_minimum_required(VERSION 3.25)
project(PikaOSInstallFixture LANGUAGES NONE)
set(CMAKE_INSTALL_BINDIR bin)
set(CMAKE_INSTALL_DATADIR share)
set(GIR_FILE "${CMAKE_CURRENT_BINARY_DIR}/WaylandShader-1.0.gir")
set(TYPELIB_FILE "${CMAKE_CURRENT_BINARY_DIR}/WaylandShader-1.0.typelib")
find_program(GLIB_COMPILE_SCHEMAS glib-compile-schemas REQUIRED)
''' + install_rules)
            prefix = root / "user prefix"
            subprocess.run(["cmake", "-S", str(source), "-B", str(build),
                            "-DCMAKE_INSTALL_PREFIX=" + str(prefix),
                            "-DLIBRASHADER_LIBRARY=" + str(link)], check=True)
            subprocess.run(["cmake", "--build", str(build), "--target", "gnome_schemas"], check=True)
            stage = root / "stage"
            subprocess.run(["cmake", "--install", str(build)],
                           env=dict(os.environ, DESTDIR=str(stage)), check=True)
            installed = stage / str(prefix).lstrip("/")
            extension = installed / "share/gnome-shell/extensions/waylandshader@man33li.github.com"
            dso = extension / "native/libwaylandshader-rashader.so.2"
            self.assertFalse(dso.is_symlink())
            self.assertEqual(dso.read_bytes(), private.read_bytes())
            self.assertEqual(json.loads((extension / "metadata.json").read_text())["shell-version"], ["51"])
            expected = {
                "extension.js", "metadata.json", "schemas/gschemas.compiled",
                "schemas/org.gnome.shell.extensions.waylandshader.gschema.xml",
                "native/libwaylandshader-gnome.so", "native/libwaylandshader-rashader.so.2",
                "native/WaylandShader-1.0.gir", "native/WaylandShader-1.0.typelib",
            }
            self.assertEqual({str(p.relative_to(extension)) for p in extension.rglob("*") if p.is_file()}, expected)
            self.assertTrue((installed / "bin/waylandshader-gnomectl").is_file())
            self.assertTrue((installed / "bin/waylandshader-gnome-controller").is_file())
            self.assertTrue((installed / "share/applications/org.waylandshader.GnomeController.desktop").is_file())


if __name__ == "__main__":
    unittest.main()
