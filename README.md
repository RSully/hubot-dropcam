# hubot-dropcam

This is a script that allows you to view your Dropcams from Hubot.

## Configuration

Depending on which environment variables you set hubot-dropcam will behave differently.

- `HUBOT_DROPCAM_USERNAME`, `HUBOT_DROPCAM_PASSWORD`
	- Required, login credentials for Dropcam website
	- *Can* be credentials for a hubot-only account that your cameras are shared with.
- `HUBOT_DROPCAM_BLACKLIST`
	- A comma-separated list of Dropcam UUIDs to ignore.
- `DEBUG`
	- If set, hubot-dropcam will be a bit more noisy (*insecure*)
- `HUBOT_DROPCAM_S3_ACCESS_KEY_ID`, `HUBOT_DROPCAM_S3_SECRET_ACCESS_KEY`, `HUBOT_DROPCAM_S3_BUCKET`
	- The default option is to save your captures to an s3 bucket. You'll need all 3 of these variables.
- `HEROKU_URL`
	- If the s3 variables are not set, hubot-dropcam will revert to saving images to your hubot directory and send links using this URL.
