## Nexcessnet_Turpentine Varnish v3 VCL Template

## Backends

{{default_backend}}

## Custom Subroutines
{{sub_normalize_user_agent}}
#https://www.varnish-cache.org/trac/wiki/VCLExampleNormalizeUserAgent
sub normalize_user_agent {
    if (req.http.User-Agent ~ "MSIE") {
        set req.http.X-Normalized-User-Agent = "msie";
    } else if (req.http.User-Agent ~ "Firefox") {
        set req.http.X-Normalized-User-Agent = "firefox";
    } else if (req.http.User-Agent ~ "Safari") {
        set req.http.X-Normalized-User-Agent = "safari";
    } else if (req.http.User-Agent ~ "Chrome") {
        set req.http.X-Normalized-User-Agent = "chrome";
    } else if (req.http.User-Agent ~ "Opera Mini/") {
        set req.http.X-Normalized-User-Agent = "opera-mini";
    } else if (req.http.User-Agent ~ "Opera Mobi/") {
        set req.http.X-Normalized-User-Agent = "opera-mobile";
    } else if (req.http.User-Agent ~ "Opera") {
        set req.http.X-Normalized-User-Agent = "opera";
    } else {
        set req.http.X-Normalized-User-Agent = "nomatch";
    }
}

{{sub_normalize_encoding}}
#https://www.varnish-cache.org/trac/wiki/VCLExampleNormalizeAcceptEncoding
sub normalize_encoding {
    if (req.http.Accept-Encoding) {
        if (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } else if (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unkown algorithm
            unset req.http.Accept-Encoding;
        }
    }
}

{{sub_normalize_host}}
sub normalize_host {
    if (req.http.Host) {
        if(req.http.Host !~ "^{{normalize_host_target}}$") {
            set req.http.Host = "{{normalize_host_target}}";
        }
    }
}

## Varnish Subroutines

sub vcl_recv {
    if (req.restarts == 0) {
        if (req.http.x-forwarded-for) {
            set req.http.X-Forwarded-For =
                req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    if (req.request != "GET" &&
            req.request != "HEAD" &&
            req.request != "PUT" &&
            req.request != "POST" &&
            req.request != "TRACE" &&
            req.request != "DELETE" &&
            req.request != "OPTIONS") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

    if (req.request != "GET" && req.request != "HEAD") {
        /* We only deal with GET and HEAD by default */
        return (pass);
    }

    {{normalize_encoding}}
    {{normalize_user_agent}}
    {{normalize_host}}

    if (req.url ~ "{{url_base_regex}}") {
        if (req.url ~ "{{url_base_regex}}(?:{{url_excludes}})") {
            return (pass);
        }
        if (req.http.Cookie ~ "{{cookie_excludes}}") {
            return (pass);
        }
        if ({{enable_get_excludes}}) {
            if (req.url ~ "(?:[?&](?:{{get_param_excludes}})(?=[&=]|$))") {
                return (pass);
            }
        }
        unset req.http.Cookie;
        return (lookup);
    }
    # else it's not part of magento so do default handling (doesn't help
    # things underneath magento but can't detect that)
}

sub vcl_pipe {
    set req.http.connection = "close";
    return (pipe);
}

# sub vcl_pass {
#     return (pass);
# }

sub vcl_hash {
    hash_data(req.url);
    if (req.http.Host) {
        hash_data(req.http.Host);
    } else {
        hash_data(server.ip);
    }
    if (req.http.X-Normalized-User-Agent) {
        hash_data(req.http.X-Normalized-User-Agent);
    }
    if (req.http.Accept-Encoding) {
        hash_data(req.http.Accept-Encoding);
    }
    return (hash);
}

# sub vcl_hit {
#     return (deliver);
# }
#
# sub vcl_miss {
#     return (fetch);
# }
#

sub vcl_fetch {
    set req.grace = {{grace_period}}s;

    if (req.http.Cookie ~ "{{cookie_excludes}}" ||
        beresp.http.Set-Cookie ~ "{{cookie_excludes}}") {
        return (deliver);
    } else if (beresp.http.X-Varnish-Bypass) {
        set beresp.ttl = {{grace_period}}s;
        return (hit_for_pass);
    } else {
        if({{debug_headers}}) {
            set beresp.http.X-Varnish-Set-Cookie = beresp.http.Set-Cookie;
        }
        unset beresp.http.Set-Cookie;
        unset beresp.http.Cache-Control;
        unset beresp.http.Expires;
        unset beresp.http.Pragma;
        unset beresp.http.Cache;
        unset beresp.http.Age;
        {{url_ttls}}
        set beresp.ttl = {{default_ttl}}s;
    }
}

# sub vcl_fetch {
#     if (beresp.ttl <= 0s ||
#         beresp.http.Set-Cookie ||
#         beresp.http.Vary == "*") {
# 		/*
# 		 * Mark as "Hit-For-Pass" for the next 2 minutes
# 		 */
# 		set beresp.ttl = 120 s;
# 		return (hit_for_pass);
#     }
#     return (deliver);
# }

#https://www.varnish-cache.org/trac/wiki/VCLExampleHitMissHeader
sub vcl_deliver {
    if ({{debug_headers}}) {
        if (obj.hits > 0) {
            set resp.http.X-Varnish-Hits = "HIT: " + obj.hits;
        } else {
            set resp.http.X-Varnish-Hits = "MISS";
        }
    }
}

# sub vcl_error {
#     set obj.http.Content-Type = "text/html; charset=utf-8";
#     set obj.http.Retry-After = "5";
#     synthetic {"
# <?xml version="1.0" encoding="utf-8"?>
# <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
#  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
# <html>
#   <head>
#     <title>"} + obj.status + " " + obj.response + {"</title>
#   </head>
#   <body>
#     <h1>Error "} + obj.status + " " + obj.response + {"</h1>
#     <p>"} + obj.response + {"</p>
#     <h3>Guru Meditation:</h3>
#     <p>XID: "} + req.xid + {"</p>
#     <hr>
#     <p>Varnish cache server</p>
#   </body>
# </html>
# "};
#     return (deliver);
# }
#
# sub vcl_init {
# 	return (ok);
# }
#
# sub vcl_fini {
# 	return (ok);
# }
