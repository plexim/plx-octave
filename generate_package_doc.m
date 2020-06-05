#
# tested with generate_html-0.3.1
#

pkg('load', 'generate_html');

opt = get_html_options(struct());

opt.include_overview = true;
opt.include_package_page = false;
opt.css = "octave.css";

opt.header = @ (opts, pars, vpars) sprintf ("\
    <!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\"\
    \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n\
    <html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"en\" xml:lang=\"en\">\n\
    <head>\n\
        <meta http-equiv=\"content-type\" content=\"text/html; charset=%s\" />\n\
        <meta name=\"date\" content=\"%s\" />\n\
        <meta name=\"generator\" content=\"generate_html %s\" />\n\
        <title>%s</title>\n\
        <link rel=\"stylesheet\" type=\"text/css\" href=\"%s\" />\n\
        </head>\n\
        <body>",
    opts.charset,
    pars.gen_date, pars.ghv,
    opts.title(opts, pars, vpars),
    fullfile(vpars.root, opts.css));

opt.footer = @(opts, pars, vpars) sprintf ("<p>Package: <a href=\"%s\">%s</a></p>\n</body></html>",
    fullfile (vpars.pkgroot, "overview.html"),
    pars.package);

generate_package_html("control", "octave-package-doc", opt)
generate_package_html("signal", "octave-package-doc", opt)

