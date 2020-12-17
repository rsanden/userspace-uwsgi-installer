import sys
def application(env, start_response):
    start_response('200 OK', [('Content-Type','text/html')])
    return [f'Python {sys.version} -- WSGI '.encode() + env['uwsgi.version']]
