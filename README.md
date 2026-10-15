## What

This is a small script to perform all the tasks that are necessary to create a private/public keypair for 
ssh-authentication for password-less connecting to a remote server. Additionally it performs some checks and 
adjusts file-permissions both locally and on the remote server to avoid some common pitfalls.

## Why

Because I failed every time I tried to do this manually.

## How

### Preconditions

You need to be able to connect to the remote server with ssh and a username and password.

Alternatively, if you already have a key that is authorized on the target (for example because you
already use another host alias, or reach the target via a jumphost), you can pass it with
`-a/--auth-key` and then no password will be asked at all.

### Grab it

    git clone https://github.com/centic9/generate-and-send-ssh-key.git

### Run it

The script expects some commandline arguments which specify which key should be transferred/created and 
where it should be sent to:

    -u (--user) <username>, default: $USER
    -f (--file) <file>,     default: ~/.ssh/id_test
    -h (--host) <hostname>, default: host
     
    -p (--port)    <port>, default: <default ssh port>
    -k (--keysize) <size>, default: 2048
    -t (--keytype) <type>, default: rsa
    
    -P(--passphrase) <key-passphrase>, default: <empty>
    -a (--auth-key)  <key already authorized on the target>, default: <none, asks for password>
    -c (--comment)   <marker for the public key>, default: <ssh-keygen default, i.e. user@host>

You should at least set `--user`, `--file`, and `--host`.  

    cd generate-and-send-ssh-key
    ./generate-and-send-ssh-key.sh --user bob --host myhost

This will ask for the password of the target host at least once, probably twice, if the permissions are not set correctly yet.

If the key-file does not exist yet, a new key will be generated.

If you already have a key that works for the target (another host alias, or via a jumphost) you can
avoid the password entirely by passing it with `--auth-key`; that key is only used to log in during
the transfer, the key that gets created/installed is still the one from `--file`:

    ./generate-and-send-ssh-key.sh --user bob --host myhost -a ~/.ssh/id_already_working

Note that `ssh-copy-id` uses `-i` for the key being installed, so the bootstrap key is passed on as
`-o IdentityFile=` internally.

### "All keys were skipped because they already exist on the remote system"

That `ssh-copy-id` warning is not an error. It logs in with the key first, and if the login works it
assumes the key is already installed and uploads nothing. The script now checks the remote
`authorized_keys` itself and prints either "Verified: the key is present" or "Not found", so the
warning alone no longer decides whether you are done.

With `--auth-key` the warning is misleading: the login succeeds through the bootstrap key, so
`ssh-copy-id` skips a key that is not installed yet. The script passes `-f` in that case, which
skips the check and appends the key.

To change only the marker on a key that is already installed, rewrite that one line on the remote
instead of re-uploading (fetch, edit locally, push back):

    ssh <host> 'cat ~/.ssh/authorized_keys' > /tmp/ak
    KEY=$(awk '{print $1" "$2}' <key>.pub)
    awk -v k="$KEY" -v c="you@example.com" '{ if (index($0,k)) printf "%s %s\n", k, c; else print }' \
        /tmp/ak > /tmp/ak.new
    cat /tmp/ak.new | ssh <host> 'cat > ~/.ssh/authorized_keys'

### The marker at the end of the key

A public key is `<type> <base64> <comment>`, and that last field is copied verbatim into the remote
`authorized_keys`. It is a free-form label only - ssh never reads it, and no email is looked up
anywhere. By default `ssh-keygen` writes `user@host` of the machine where the key was created, so
pass `--comment` if you would rather see something like your email or a nickname there:

    ./generate-and-send-ssh-key.sh --user bob --host myhost -c "bob@example.com"

This only applies to keys that are created by the script; an existing key keeps its current comment.
To change that one in place, without touching the key material itself, run

    ssh-keygen -c -C "bob@example.com" -f ~/.ssh/id_test

### Enjoy

Now you should be able to connect to the machine via ```ssh -i $FILENAME $USER@$HOST```.  
If you use the filename 
```~/.ssh/id_rsa``` you can omit the "-i" argument to ssh.

## Support this project

If you find this tool useful and would like to support it, you can [Sponsor the author](https://github.com/sponsors/centic9)

## Caveat

This script will remove write access to your home-directory for "group" and "other" on the remote server because 
ssh-public/private key authentication will not work otherwise.  

So if there are processes running as different user, 
writing data to this directory may fail for them after this script is run.

## Related documents

* http://linux.die.net/man/1/ssh-copy-id
* https://en.wikipedia.org/wiki/Ssh-keygen
* http://www.openbsd.org/cgi-bin/man.cgi/OpenBSD-current/man1/ssh-keygen.1?query=ssh-keygen&sec=1
* http://www.thegeekstuff.com/2008/11/3-steps-to-perform-ssh-login-without-password-using-ssh-keygen-ssh-copy-id/
* http://askubuntu.com/questions/4830/easiest-way-to-copy-ssh-keys-to-another-machine
* http://www.daveperrett.com/articles/2010/09/14/ssh-authentication-refused/

## Documentation on SSH login issues

* How to tackle slow login: https://jrs-s.net/2017/07/01/slow-ssh-logins/
* Slow SSH logins? Try to restart services `systemd-logind` and `dbus` on the ssh server

#### Licensing

   Copyright 2015-2022 Dominik Stadler

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
