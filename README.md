# NixOS Caddy IPFS Web Host

**TODO** add more details and simplify this, currently this is a braindump with too much going on with too many edge cases

This sets up a NixOS server where you can upload your website to IPFS and then Caddy (with custom plugins) will serve it. This is currently hosting [my personal website](https://karmanyaah.malhotra.cc) and [UnifiedPush.org](https://unifiedpush.org).
 

Here is an [example GitHub action](https://github.com/UnifiedPush/documentation/blob/main/.github/workflows/main.yml#L39-L66) deploying to this server:
```yaml
      - name: Build
        run: hugo --minify
      # thx https://github.com/wlixcc/SFTP-Deploy-Action/blob/master/entrypoint.sh for details on this
      - name: Connect to ssh in BG
        timeout-minutes: 2
        run: | 
          echo "${{ secrets.SSHKEY }}" > ../privkey
          chmod 600 ../privkey
          host unifiedpush.org
          ssh -o StrictHostKeyChecking=no nobody@unifiedpush.org -i ../privkey -L 5001:localhost:5001 -fTN
      - name: ipfs upload
        uses: aquiladev/ipfs-action@v0.3.1
        id: deploy
        timeout-minutes: 2
        with:
          path: ./public
          service: ipfs
          verbose: true
          host: localhost
          port: 5001
          protocol: http
          pin: false
      - name: DNSLINK
        run: 'curl -D- -X PUT -H "Content-Type: application/json" -H "Authorization: Apikey ${{ secrets.GandiAPI }}" -d "{\"rrset_ttl\": 300,\"rrset_values\": [\"dnslink=/ipfs/${{ steps.deploy.outputs.HASH }}\"]}" https://api.gandi.net/v5/livedns/domains/unifiedpush.org/records/_dnslink/TXT'
```


or an example set of bash script(s) deploying to this server:

First connect to the server with `ssh nobody@${1:-mydomain.cc} -L 5001:localhost:5001 -vTN` and to deploy run `JEKYLL_ENV="production" bundle exec jekyll build; DOMAIN="mydomain.cc" DIR="./_site" ./_deploy.sh` with the following `_deploy.sh`:
```sh
#!/bin/bash

# If a command fails then the deploy stops
set -e

printf "\033[0;32mDeploying updates to ipfs for $DOMAIN...\033[0m\n"

BW_ENTRY=cloudflare_website_token
LOC="/website/$DOMAIN"
CUSTOM_IPFS_OPTIONS="--api /ip4/127.0.0.1/tcp/5001 $CUSTOM_IPFS_OPTIONS"
CID=$(ipfs add $DIR -rpQ --pin=false --cid-version=1 $CUSTOM_IPFS_OPTIONS $CUSTOM_IPFS_ADD_OPTIONS)
echo added to $CID

ipfs files mkdir -p "$LOC" $CUSTOM_IPFS_OPTIONS
if ipfs files ls -l "$LOC" $CUSTOM_IPFS_OPTIONS| grep -q $CID; then
        echo already added $CID to $LOC
else
        echo adding $CID to $LOC
        ipfs files cp /ipfs/$CID "$LOC/$(date +%F_%T)" $CUSTOM_IPFS_OPTIONS
fi

RECORD_DOMAIN="_dnslink.$DOMAIN"

# password is token and custom fields called zone and for each record
SECRETS="$(rbw get $BW_ENTRY --full)"
CLOUDFLARE_TOKEN="$(echo "$SECRETS" | head -n 1)"
ZONE_ID="$(echo "$SECRETS" | grep -i zone | cut -d ' ' -f 2 )"

function curll {
        curl -s -H "Authorization: Bearer $CLOUDFLARE_TOKEN" -w '\n' -H "Content-Type:application/json" $@
}

RECORD_ID=$(curll "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_DOMAIN"  | jq ".result[0].id" -r)
echo -n "dns $ZONE_ID/$RECORD_ID success: "
curll "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -X PATCH --data "{\"content\":\"dnslink=/ipfs/$CID\"}" | jq '.success'
``` 
