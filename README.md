# Netflix Job Watcher

See [Netflix Culture Blog Post](https://allcentury.github.io/2024/09/21/netflix-job-analysis/)

This is a small lambda service running on the serverless framework that will look at Netflix's job's API for a given string and
if the service has never seen the job before, it will send an email notification.

Note that the email must be verified in AWS console before this can work.

Before deploying, run:

```
bundle install --deployment
```

then to deploy:

```
sls deploy
```
