# Cloudflare DDNS Updater

This is a simple script to update your Cloudflare DDNS records. It will update your Cloudflare DDNS records with your current IP address. This script is meant to be run periodically.
Its support telegram notification too.

## Dependencies

- curl
- jq

## Usage

Before using it, be sure to change the variables in the script.

```
./cloudflare.sh
```

## Usage with crontab

```
# Run every 5 minutes
*/5 * * * * /path/to/cloudflare.sh
```

## License

MIT
