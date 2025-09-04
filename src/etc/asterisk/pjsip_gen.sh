#!/bin/bash


pjsip_gen(){

################################################################################
## bold red
local LOG_EMERG="<0>[EMERGENCY] "
local LOG_ALERT="<1>[ALERT] "
local LOG_CRIT="<2>[CRITICAL] "
local LOG_ERR="<3>[ERROR] "
## bold white
local LOG_WARNING="<4>[WARNING] "
local LOG_NOTICE="<5>[NOTICE] "
## normally
local LOG_INFO="<6>[INFO] "
local LOG_DEBUG="<7>[DEBUG] "


################################################################################
sed -i '/^\[default\]$/,/^\[/ {/^\[/b; d; }' voicemail.conf



################################################################################
echo -n > pjsip.conf || { echo ${LOG_ERR} "Can't create file pjsip.conf." ; exit 1 ;}
echo ";===============================================================================
;======================================================================PJSIP_GEN
[global]
type=global
default_from_user=Bruno
user_agent=DIGITRO-PBX


;===============================================================================
;=====================================================================TRANSPORTS
[transport-ipv4-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060
local_net=192.168.160.0/20
;local_net=10.142.0.2/32

[transport-ipv4-tls]
type=transport
protocol=tls
;method=tlsv1
method=SSLv23
cert_file=/etc/asterisk/keys/serverchain.pem
priv_key_file=/etc/asterisk/keys/server.key
;ca_list_file=/etc/asterisk/keys/trusted_cas.crt
verify_client=no
verify_server=no
bind=0.0.0.0:5061
local_net=192.168.160.0/20
;local_net=10.142.0.2/32
;external_media_address=34.148.128.58
;external_signaling_address=34.148.128.58
cipher=0x002f

[transport-ipv4-udp-option]
type=transport
protocol=udp
bind=0.0.0.0:5061


" >> pjsip.conf






echo ";===============================================================================
;===================================================UNREGISTERED TRUNK TEMPLATES
[aor-UNREG-TRUNK](!)
type=aor

[endpoint-UNREG-TRUNK](!)
type=endpoint
context=default
message_context=default-messages
disallow=all
allow=ulaw,alaw,g729,h264,vp8
dtmf_mode=info
sdp_session=bruno
allow_subscribe=yes
send_pai=yes
send_rpid=yes
identify_by=username,auth_username
mwi_subscribe_replaces_unsolicited=yes
ice_support=no
direct_media=no
force_rport=yes
rtp_symmetric=yes
rewrite_contact=yes

[identify-UNREG-TRUNK](!)
type=identify


" >> pjsip.conf

for ((i=109;i<=109;i++)); do
echo ";================================
[$(printf '%03d' ${i})](aor-UNREG-TRUNK)
contact=sip:192.168.169.6
mailboxes=$(printf '%03d' ${i})@default
@DDI=55
@DDD=61

[$(printf '%03d' ${i})](endpoint-UNREG-TRUNK)
contact_user=$(printf '%03d' ${i})
aors=$(printf '%03d' ${i})
mailboxes=$(printf '%03d' ${i})@default
media_encryption=sdes
context=in-ip
message_context=in-ip-messages

[$(printf '%03d' ${i})](identify-UNREG-TRUNK)
endpoint=$(printf '%03d' ${i})
match=192.168.169.6

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done







echo "



;===============================================================================
;=======================================OUTBOUND REGISTRATION ENDPOINT TEMPLATES
[registration-OUT-REG-ENDPOINT](!)
type=registration
retry_interval=30
forbidden_retry_interval=30
max_retries=1000
expiration=300

[aor-OUT-REG-ENDPOINT](!)
type=aor

[auth-OUT-REG-ENDPOINT](!)
type=auth
auth_type=userpass
password=Teste123

[endpoint-OUT-REG-ENDPOINT](!)
type=endpoint
context=default
message_context=default-messages
disallow=all
allow=ulaw,alaw,g729,h264,vp8
dtmf_mode=info
sdp_session=bruno
allow_subscribe=yes
send_pai=yes
send_rpid=yes
identify_by=username,auth_username
mwi_subscribe_replaces_unsolicited=yes
ice_support=no
direct_media=no
force_rport=yes
rtp_symmetric=yes
rewrite_contact=yes

[identify-OUT-REG-ENDPOINT](!)
type=identify


" >> pjsip.conf

for ((i=120;i<=119;i++)); do
echo ";================================
[$(printf '%03d' ${i})](registration-OUT-REG-ENDPOINT)
contact_user=$(printf '%03d' ${i})
outbound_auth=$(printf '%03d' ${i})
client_uri=sip:$(printf '%03d' ${i})@192.168.163.51:5060\;transport=udp
server_uri=sip:192.168.163.51:5060\;transport=udp

[$(printf '%03d' ${i})](aor-OUT-REG-ENDPOINT)
contact=sip:$(printf '%03d' ${i})@192.168.163.51:5060\;transport=udp
mailboxes=$(printf '%03d' ${i})@default

[$(printf '%03d' ${i})](auth-OUT-REG-ENDPOINT)
username=$(printf '%03d' ${i})

[$(printf '%03d' ${i})](endpoint-OUT-REG-ENDPOINT)
contact_user=$(printf '%03d' ${i})
aors=$(printf '%03d' ${i})
;auth=$(printf '%03d' ${i})
outbound_auth=$(printf '%03d' ${i})
mailboxes=$(printf '%03d' ${i})@default
;media_encryption=sdes

[$(printf '%03d' ${i})](identify-OUT-REG-ENDPOINT)
endpoint=$(printf '%03d' ${i})
match=192.168.163.51,192.168.170.2
match_header=sip:$(printf '%03d' ${i})@*

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done







echo "



;===============================================================================
;=======================================INBOUND REGISTRATION ENDPOINT TEMPLATES
[aor-IN-REG-ENDPOINT](!)
type=aor
max_contacts=40
remove_existing=yes
 
[auth-IN-REG-ENDPOINT](!)
type=auth
auth_type=userpass
password=Teste123

[endpoint-IN-REG-ENDPOINT](!)
type=endpoint
context=default
message_context=default-messages
disallow=all
allow=ulaw,alaw,g729,h264,vp8
dtmf_mode=info
sdp_session=bruno
allow_subscribe=yes
send_pai=yes
send_rpid=yes
identify_by=username,auth_username
mwi_subscribe_replaces_unsolicited=yes
ice_support=no
direct_media=no
force_rport=yes
rtp_symmetric=yes
rewrite_contact=yes

" >> pjsip.conf

for ((i=100;i<=107;i++)); do
echo ";================================
[$(printf '%03d' ${i})](aor-IN-REG-ENDPOINT)
mailboxes=$(printf '%03d' ${i})@default
max_contacts=1
@DDI=55
@DDD=21
 
[$(printf '%03d' ${i})](auth-IN-REG-ENDPOINT)
username=$(printf '%03d' ${i})

[$(printf '%03d' ${i})](endpoint-IN-REG-ENDPOINT)
contact_user=$(printf '%03d' ${i})
aors=$(printf '%03d' ${i})
auth=$(printf '%03d' ${i})
mailboxes=$(printf '%03d' ${i})@default
media_encryption=sdes
context=in3-oaccount3-oroute2
message_context=in3-oaccount3-oroute2-messages

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done

for ((i=110;i<=110;i++)); do
echo ";================================
[$(printf '%03d' ${i})](aor-IN-REG-ENDPOINT)
mailboxes=$(printf '%03d' ${i})@default
max_contacts=1
@DDI=55
@DDD=61
 
[$(printf '%03d' ${i})](auth-IN-REG-ENDPOINT)
username=$(printf '%03d' ${i})

[$(printf '%03d' ${i})](endpoint-IN-REG-ENDPOINT)
contact_user=$(printf '%03d' ${i})
aors=$(printf '%03d' ${i})
auth=$(printf '%03d' ${i})
mailboxes=$(printf '%03d' ${i})@default
media_encryption=sdes
context=in-oaccount3-oroute2
message_context=in-oaccount3-oroute2-messages

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done

for ((i=111;i<=112;i++)); do
echo ";================================
[$(printf '%03d' ${i})](aor-IN-REG-ENDPOINT)
mailboxes=$(printf '%03d' ${i})@default
max_contacts=1
@DDI=55
@DDD=48
 
[$(printf '%03d' ${i})](auth-IN-REG-ENDPOINT)
username=$(printf '%03d' ${i})

[$(printf '%03d' ${i})](endpoint-IN-REG-ENDPOINT)
contact_user=$(printf '%03d' ${i})
aors=$(printf '%03d' ${i})
auth=$(printf '%03d' ${i})
mailboxes=$(printf '%03d' ${i})@default
media_encryption=sdes
context=in-oaccount3-oroute2
message_context=in-oaccount3-oroute2-messages

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done

for ((i=113;i<=113;i++)); do
echo ";================================
[$(printf '%03d' ${i})](aor-IN-REG-ENDPOINT)
mailboxes=$(printf '%03d' ${i})@default
max_contacts=1
@DDI=55
@DDD=48
 
[$(printf '%03d' ${i})](auth-IN-REG-ENDPOINT)
username=$(printf '%03d' ${i})

[$(printf '%03d' ${i})](endpoint-IN-REG-ENDPOINT)
contact_user=$(printf '%03d' ${i})
aors=$(printf '%03d' ${i})
auth=$(printf '%03d' ${i})
mailboxes=$(printf '%03d' ${i})@default
media_encryption=sdes
context=in2-oaccount3-oroute2
message_context=in3-oaccount3-oroute2-messages

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done

c="aaa"
for ((i=4000;i<=4003;i++)); do
echo ";================================
[${c}$(printf '%04d' ${i})](aor-IN-REG-ENDPOINT)
mailboxes=${c}$(printf '%04d' ${i})@default
max_contacts=1
@DDI=55
@DDD=48
 
[${c}$(printf '%04d' ${i})](auth-IN-REG-ENDPOINT)
username=${c}$(printf '%04d' ${i})

[${c}$(printf '%04d' ${i})](endpoint-IN-REG-ENDPOINT)
contact_user=${c}$(printf '%04d' ${i})
aors=${c}$(printf '%04d' ${i})
auth=${c}$(printf '%04d' ${i})
mailboxes=${c}$(printf '%04d' ${i})@default
media_encryption=sdes
context=in4-oaccount7-oroute0
message_context=in4-oaccount7-oroute0-messages

" >> pjsip.conf

sed -i "/^\[default\]$/a ${c}$(printf '%04d' ${i}) => 4567,${c}$(printf '%04d' ${i}),${c}$(printf '%04d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done


for ((i=1000;i<=1033;i++)); do
echo ";================================
[$(printf '%04d' ${i})](aor-IN-REG-ENDPOINT)
mailboxes=$(printf '%04d' ${i})@default
 
[$(printf '%04d' ${i})](auth-IN-REG-ENDPOINT)
username=$(printf '%04d' ${i})

[$(printf '%04d' ${i})](endpoint-IN-REG-ENDPOINT)
contact_user=$(printf '%04d' ${i})
aors=$(printf '%04d' ${i})
auth=$(printf '%04d' ${i})
mailboxes=$(printf '%04d' ${i})@default
media_encryption=sdes

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done

for ((i=3000;i<=3099;i++)); do
echo ";================================
[$(printf '%04d' ${i})](aor-IN-REG-ENDPOINT)
mailboxes=$(printf '%04d' ${i})@default
 
[$(printf '%04d' ${i})](auth-IN-REG-ENDPOINT)
username=$(printf '%04d' ${i})

[$(printf '%04d' ${i})](endpoint-IN-REG-ENDPOINT)
contact_user=$(printf '%04d' ${i})
aors=$(printf '%04d' ${i})
auth=$(printf '%04d' ${i})
mailboxes=$(printf '%04d' ${i})@default
;media_encryption=sdes

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done

for ((i=3100;i<=3199;i++)); do
echo ";================================
[$(printf '%04d' ${i})](aor-IN-REG-ENDPOINT)
mailboxes=$(printf '%04d' ${i})@default
 
[$(printf '%04d' ${i})](auth-IN-REG-ENDPOINT)
username=$(printf '%04d' ${i})

[$(printf '%04d' ${i})](endpoint-IN-REG-ENDPOINT)
contact_user=$(printf '%04d' ${i})
aors=$(printf '%04d' ${i})
auth=$(printf '%04d' ${i})
mailboxes=$(printf '%04d' ${i})@default
media_encryption=sdes

" >> pjsip.conf

sed -i "/^\[default\]$/a $(printf '%03d' ${i}) => 4567,$(printf '%03d' ${i}),$(printf '%03d' ${i})@default,,attach=no|emailsubject=You have a new voicemail.|emailbody=Press Mail or call *131.|tz=central|maxmsg=10" voicemail.conf

done



}



pjsip_gen







