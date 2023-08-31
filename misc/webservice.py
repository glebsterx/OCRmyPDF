#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2019 James R. Barlow
# SPDX-License-Identifier: AGPL-3.0-or-later

"""This is a simple web service/HTTP wrapper for OCRmyPDF.

This may be more convenient than the command line tool for some Docker users.
Note that OCRmyPDF uses Ghostscript, which is licensed under AGPLv3+. While
OCRmyPDF is under GPLv3, this file is distributed under the Affero GPLv3+ license,
to emphasize that SaaS deployments should make sure they comply with
Ghostscript's license as well as OCRmyPDF's.
"""

from __future__ import annotations

import os
import shlex
from subprocess import run
from tempfile import TemporaryDirectory

from flask import Flask, Response, request, send_from_directory, send_file
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.secret_key = "secret"
app.config['MAX_CONTENT_LENGTH'] = 50_000_000
app.config.from_envvar("OCRMYPDF_WEBSERVICE_SETTINGS", silent=True)

ALLOWED_EXTENSIONS = {"pdf"}


def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def do_ocrmypdf(file):
    uploaddir = TemporaryDirectory(prefix="ocrmypdf-upload")
    downloaddir = TemporaryDirectory(prefix="ocrmypdf-download")

    filename = secure_filename(file.filename)
    up_file = os.path.join(uploaddir.name, filename)
    file.save(up_file)

    down_file = os.path.join(downloaddir.name, filename)

    cmd_args = [arg for arg in shlex.split(request.form["params"])]
    if "--sidecar" in cmd_args:
        return Response("--sidecar not supported", 501, mimetype='text/plain')

    ocrmypdf_args = ["ocrmypdf", *cmd_args, up_file, down_file]
    proc = run(ocrmypdf_args, capture_output=True, encoding="utf-8", check=False)
    if proc.returncode != 0:
        stderr = proc.stderr
        return Response(stderr, 400, mimetype='text/plain')

    return send_from_directory(downloaddir.name, filename)


def root_dir():  # pragma: no cover
    return os.path.abspath(os.path.dirname(__file__))


def get_file(filename):  # pragma: no cover
    try:
        src = os.path.join(root_dir(), filename)
        # Figure out how flask returns static files
        # Tried:
        # - render_template
        # - send_file
        # This should not be so non-obvious
        return open(src).read()
    except IOError as exc:
        return str(exc)


@app.route("/", methods=["GET", "POST"])
def upload_file():
    if request.method == "POST":
        if "file" not in request.files:
            return Response("No file in POST", 400, mimetype='text/plain')
        file = request.files["file"]
        if file.filename == "":
            return Response("Empty filename", 400, mimetype='text/plain')
        if not allowed_file(file.filename):
            return Response("Invalid filename", 400, mimetype='text/plain')
        if file and allowed_file(file.filename):
            return do_ocrmypdf(file)
        return Response("Some other problem", 400, mimetype='text/plain')

    complete_path = os.path.join(root_dir(), "index.html")
    content = get_file(complete_path)
    return Response(content, "text/html")


@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def get_resource(path):  # pragma: no cover
    mimetypes = {
        ".css": "text/css",
        ".html": "text/html",
        ".js": "application/javascript",
        ".svg": "image/svg+xml",
        ".gif": "image/gif",
        ".ico": "image/x-icon",
    }
    complete_path = os.path.join(root_dir(), path)
    ext = os.path.splitext(path)[1]
    mimetype = mimetypes.get(ext, "text/html")
    if (ext == ".gif" or ext == ".ico"):
        return send_file(complete_path, mimetype=mimetype)
    else:
        return Response(get_file(complete_path), mimetype=mimetype)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
