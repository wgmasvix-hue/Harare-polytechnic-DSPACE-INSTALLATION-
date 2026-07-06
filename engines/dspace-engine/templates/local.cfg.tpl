# =============================================================================
#  ChengetAi DSpace Engine — DSpace local.cfg template
#  Rendered by install.sh — do not hand-edit on a running instance
#  Tokens: %%DSPACE_HOSTNAME%%  %%POSTGRES_PASSWORD%%  %%SMTP_HOST%%
#          %%SMTP_PORT%%  %%DSPACE_NAME%%  %%HANDLE_PREFIX%%
#          %%MAIL_FROM%%  %%PUBLIC_PROTOCOL%%
# =============================================================================

#------------------------------------------------------------------
# CORE
#------------------------------------------------------------------
dspace.dir          = /dspace
dspace.name         = %%DSPACE_NAME%%
dspace.hostname     = %%DSPACE_HOSTNAME%%
dspace.server.url   = %%PUBLIC_PROTOCOL%%://%%DSPACE_HOSTNAME%%/server
dspace.ui.url       = %%PUBLIC_PROTOCOL%%://%%DSPACE_HOSTNAME%%
default.locale      = en

#------------------------------------------------------------------
# DATABASE
#------------------------------------------------------------------
db.driver         = org.postgresql.Driver
db.url            = jdbc:postgresql://postgres:5432/dspace
db.username       = dspace
db.password       = %%POSTGRES_PASSWORD%%
db.schema         = public
db.maxconnections = 30
db.maxwait        = 5000
db.maxidle        = 10

#------------------------------------------------------------------
# SOLR
#------------------------------------------------------------------
solr.server = http://solr:8983/solr

#------------------------------------------------------------------
# EMAIL
#------------------------------------------------------------------
mail.server               = %%SMTP_HOST%%
mail.server.port          = %%SMTP_PORT%%
mail.from.address         = %%MAIL_FROM%%
mail.feedback.recipient   = %%MAIL_FROM%%
mail.admin                = %%MAIL_FROM%%
alert.recipient           = %%MAIL_FROM%%
mail.registration.notify  = %%MAIL_FROM%%

#------------------------------------------------------------------
# HANDLE
#------------------------------------------------------------------
handle.canonical.prefix = http://hdl.handle.net/
handle.prefix           = %%HANDLE_PREFIX%%

#------------------------------------------------------------------
# FILE STORAGE
#------------------------------------------------------------------
assetstore.dir = ${dspace.dir}/assetstore
upload.max     = 524288000

#------------------------------------------------------------------
# USER REGISTRATION
#------------------------------------------------------------------
user.registration = true

#------------------------------------------------------------------
# OAI-PMH
#------------------------------------------------------------------
oai.url = %%PUBLIC_PROTOCOL%%://%%DSPACE_HOSTNAME%%/server/oai/request

#------------------------------------------------------------------
# STATISTICS
#------------------------------------------------------------------
usage-statistics.authorization.admin.usage = true

#------------------------------------------------------------------
# THUMBNAILS
#------------------------------------------------------------------
thumbnail.maxwidth  = 300
thumbnail.maxheight = 300
