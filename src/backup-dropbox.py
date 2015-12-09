#!/usr/bin/env python

from __future__ import print_function
import os
import sys
import dropbox
from dropbox.rest import ErrorResponse
import urllib3

urllib3.disable_warnings()

def usage():
    print('Usage:')
    print('  setup                            Link dropbox account')
    print('  ls                               List file on Dropbox')
    print('  put <local-file> [remote-file]   Upload file to dropbox (overwrites)')
    print('  get <remote-file> [local-file]   Download file from dropbox')
    print('')
    print('Env vars:')
    print('  DROPBOX_APP_KEY      App key from dropbox')
    print('  DROPBOX_APP_SECRET   App secret from dropbox')
    print('  DROPBOX_AUTH_TOKEN   Auth token usaed to access your Dropbxo account')

try:
    app_key = os.environ['DROPBOX_APP_KEY']
    app_secret = os.environ['DROPBOX_APP_SECRET']
except KeyError as ex:
    print('Missing env var: %s' % ex)
    print('')
    print('Go to https://www.dropbox.com/developers/apps, create a new app and copy the key and secret from there.')
    sys.exit(1)

flow = dropbox.client.DropboxOAuth2FlowNoRedirect(app_key, app_secret)

if 4 < len(sys.argv) < 2 or sys.argv[1] not in [ 'setup', 'ls', 'put', 'get' ]:
    usage()
    sys.exit(1)

if sys.argv[1] == 'setup' or 'DROPBOX_AUTH_TOKEN' not in os.environ:
    authorize_url = flow.start()
    print('1. Go to: ' + authorize_url)
    print('2. Click "Allow" (you might have to log in first)')
    print('3. Copy the authorization code.')

    code = raw_input("Enter the authorization code here: ").strip()

    access_token, user_id = flow.finish(code)
    client = dropbox.client.DropboxClient(access_token)

    print('')
    print('Linked account:', client.account_info()['display_name'])
    print('Auth token:    ', access_token)
    print('')
    print('Now let\'s add it to your openshift app:')
    print('')
    print('  $ rhc env-set -a <app-name> \\')
    print('      DROPBOX_AUTH_TOKEN="%s" \\' % access_token)
    print('      DROPBOX_APP_KEY="%s" \\' % app_key)
    print('      DROPBOX_APP_SECRET="%s"' % app_secret)
    
    sys.exit(0)

elif sys.argv[1] in [ 'ls', 'put', 'get' ]:
    try:
        access_token = os.environ['DROPBOX_AUTH_TOKEN']
        client = dropbox.client.DropboxClient(access_token)
    except KeyError as ex:
        print('Missing env var: %s' % ex)
        print('To retrieve a new auth token, execute:')
        print('  $ %s setup' % sys.argv[0])
        sys.exit(1)

else:
    print('Invalid parameter:', sys.argv[1])
    usage()
    sys.exit(1)


class Command(object):
    def __init__(self, client):
        self.client = client

    def ls(self, path='/', pattern='.gz'):
        print('# Listing', path)
        files = self.client.search(path=path, query=pattern)
        print('# Total', len(files))
        if not files:
            return
        f_len = reduce(lambda a, b: a if a > b else b, ( len(f['path']) for f in files), 0) + 1
        s_len = reduce(lambda a, b: a if a > b else b, ( len(str(f['bytes'])) for f in files), 0) + 1
        s_len = max(s_len, 13)
        print('# Filename'.ljust(f_len), 'Size (bytes)'.ljust(s_len), 'Modified')
        for f in files:
            print(f['path'].ljust(f_len), str(f['bytes']).ljust(s_len), f['modified'])


    def put(self, source, target=None):
        if not target:
            target = os.path.split(source)[1]

        if source == '-':
            response = self.client.put_file(target, sys.stdin)
        else:
            with open(source, 'rb') as f:
                response = self.client.put_file(target, f)

        print(target)


    def get(self, source, target=None):
        if not target:
            target = os.path.split(source)[1]
        with self.client.get_file(source) as f:
            with open(target, 'wb') as out:
                out.write(f.read())
                out.flush()
                print('# Wrote', target, '(%s bytes)' % out.tell())


    def run(self, cmd, *args):
        method = getattr(self, cmd)
        method(*args)

cmd = Command(client)
try:
    cmd.run(*sys.argv[1:])
except ErrorResponse, ex:
    print('Error {}: {}'.format(ex.status, ex.reason))
    sys.exit(1)
