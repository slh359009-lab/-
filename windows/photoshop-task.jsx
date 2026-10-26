// Fixed Photoshop 2023 host code. The task placeholder is replaced with encoded data.
(function () {
    var task = __TASK_JSON__;
    function quote(value) {
        return '"' + String(value).replace(/[\\"\x00-\x1f]/g, function (c) {
            if (c === '\\') return '\\\\';
            if (c === '"') return '\\"';
            return '\\u' + ('0000' + c.charCodeAt(0).toString(16)).slice(-4);
        }) + '"';
    }
    function encode(value) {
        var parts = [], key;
        for (key in value) {
            if (value.hasOwnProperty(key)) {
                parts.push(quote(key) + ':' +
                    (typeof value[key] === 'number' ? String(value[key]) : quote(value[key])));
            }
        }
        return '{' + parts.join(',') + '}';
    }
    if (task.action === 'status') {
        var status = {application: app.name, version: app.version, documents: app.documents.length};
        if (app.documents.length) {
            status.active_document = app.activeDocument.name;
            status.width = Math.round(app.activeDocument.width.as('px'));
            status.height = Math.round(app.activeDocument.height.as('px'));
        }
        return encode(status);
    }
    if (task.action !== 'export_copy') throw new Error('Unsupported action');
    if (!app.documents.length) throw new Error('Open a document in Photoshop first');
    var target = new File(task.output_path);
    if (target.exists) throw new Error('Export already exists; use another file name');
    var original = app.activeDocument;
    var copy = null;
    var dialogs = app.displayDialogs;
    try {
        app.displayDialogs = DialogModes.NO;
        copy = original.duplicate();
        if (copy.mode !== DocumentMode.RGB) copy.changeMode(ChangeMode.RGB);
        copy.bitsPerChannel = BitsPerChannelType.EIGHT;
        copy.convertProfile('sRGB IEC61966-2.1', Intent.RELATIVECOLORIMETRIC, true, true);
        if (task.width && task.height) {
            var scale = Math.min(task.width / copy.width.as('px'), task.height / copy.height.as('px'));
            copy.resizeImage(new UnitValue(Math.max(1, Math.round(copy.width.as('px') * scale)), 'px'),
                new UnitValue(Math.max(1, Math.round(copy.height.as('px') * scale)), 'px'),
                null, ResampleMethod.BICUBIC);
        }
        var options;
        if (task.format === 'jpg') {
            copy.flatten();
            options = new JPEGSaveOptions();
            options.quality = task.quality;
            options.embedColorProfile = true;
        } else {
            options = new PNGSaveOptions();
            options.interlaced = false;
        }
        copy.saveAs(target, options, true, Extension.LOWERCASE);
        return encode({file: task.file_name, width: Math.round(copy.width.as('px')),
            height: Math.round(copy.height.as('px')), format: task.format});
    } finally {
        try {
            if (copy) copy.close(SaveOptions.DONOTSAVECHANGES);
        } finally {
            app.activeDocument = original;
            app.displayDialogs = dialogs;
        }
    }
}());
