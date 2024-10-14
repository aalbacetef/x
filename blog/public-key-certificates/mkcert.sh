#!/usr/bin/env bash 

set -e
set -u
set -o pipefail

# directory in which to output all certificate information
CERT_DIR="${CERT_DIR:-certs}"

# CA information
CA_NAME="${CA_NAME:-ca}"
CA_SUBJ=${CA_SUBJ:-"/C=US/O=My Dev/CN=localhost"}

# leaf certificate information
NAME="${NAME:-example}"
SUBJ=${SUBJ:-"/C=US/O=Example LLC/CN=example.localhost"}
SUBJ_ALT_NAME=${SUBJ_ALT_NAME:-"example.localhost"}

# days certificate will be valid for
DAYS="${DAYS:-7000}"

########################
# 
# Log utility function
#
########################

log() {
  now=$(date +"%H:%M:%S")
  echo "[mkcert.sh | $now]" "$@"
}


########################################################
#
# Generate a pair of RSA (4096 bit) keys in the 
# given directory in PEM format. The filenames
# will follow the format $name.pub.pem, $name.pvt.pem 
# 
# Arguments:
#   name
#   crt_dir 
#
########################################################
gen_keypair() {
  local name
  local crt_dir 

  name="$1"
  crt_dir="$2"

  openssl genpkey \
    -out "$crt_dir/$name.pvt.pem" \
    -outform PEM \
    -outpubkey "$crt_dir/$name.pub.pem" \
    -algorithm RSA \
    -pkeyopt bits:4096
}


########################################################
#
# Generate a self-signed certificate in the given 
# directory in PEM format. The filenames will follow 
# the format $name.crt.pem.
# 
# This is meant to be used for the CA certificate.
#
# Arguments:
#   name
#   crt_dir 
#   subj
#   days
#
########################################################
gen_self_signed_cert() {
  local name
  local crt_dir
  local subj
  local days

  name="$1"
  crt_dir="$2"
  subj="$3"
  days="$4"

  openssl req -x509 \
    -subj "$subj" \
    -key "$crt_dir/$name.pvt.pem" \
    -outform PEM \
    -out "$crt_dir/$name.crt.pem" \
    -days "$days"
}

########################################################
#
# Generate a certificate signing request in the given 
# directory in PEM format. The filename will follow 
# the format $name.csr.pem.
# 
# Arguments:
#   name
#   crt_dir 
#   subj
#   san (subject alt name)
# 
# Note: there is a bug in some openssl versions where
# they do not pass through the:
#    basicConstraints = CA:FALSE
#
#
########################################################
gen_csr() {
  local name
  local crt_dir
  local subj
  local san

  name="$1"
  crt_dir="$2"
  subj="$3"
  san="$4"

  openssl req \
    -inform PEM \
    -outform PEM \
    -new \
    -key "$crt_dir/$name.pvt.pem" \
    -addext "basicConstraints = CA:FALSE" \
    -addext "subjectAltName = DNS:$san" \
    -subj "$subj" \
    -out "$crt_dir/$name.csr.pem"
}

#################################################################
#
# Sign a certificate signing request, copying all extensions.
# The certificate filename will follow the format $name.crt.pem.
# 
# Arguments:
#   name
#   crt_dir 
#   ca_name 
#   days
#
# Notes: It expects the CA certificate is $crt_dir/$ca_name.crt.pem, 
# and the key is $crt_dir/$ca_name.pvt.pem.
#  
#################################################################
sign_csr() {
  local name 
  local crt_dir
  local ca_name
  local days 

  name="$1"
  crt_dir="$2"
  ca_name="$3"
  days="$4"

  openssl req \
    -in "$crt_dir/$name.csr.pem" \
    -inform PEM \
    -CA "$crt_dir/$ca_name.crt.pem" \
    -CAkey "$crt_dir/$ca_name.pvt.pem" \
    -copy_extensions copyall \
    -days "$days" \
    -outform PEM \
    -out "$crt_dir/$name.crt.pem"
}


###########
#
# Main 
#
###########

log "variables:"
log "  CERT_DIR: $CERT_DIR"
log "  CA_NAME: $CA_NAME"
log "  CA_SUBJ: $CA_SUBJ"
log "  NAME: $NAME"
log "  SUBJ: $SUBJ"
log "  SUBJ_ALT_NAME: $SUBJ_ALT_NAME"
log "  DAYS: $DAYS"


# create certificate directory if not exists
log "checking if certificate directory '$CERT_DIR' exists..."
if ! test -d "$CERT_DIR"; then 
  log "  not found, creating..."
  mkdir -p "$CERT_DIR"
fi 
log "done"

# check if CA keys exist
log "checking if CA keys exist..."

if ! test -f "$CERT_DIR/$CA_NAME.pvt.pem"; then 
  log "  generating CA keys..."
  gen_keypair "$CA_NAME" "$CERT_DIR"
fi

if ! test -f "$CERT_DIR/$CA_NAME.pub.pem"; then 
  log "  generating CA keys..."
  gen_keypair "$CA_NAME" "$CERT_DIR"
fi

log "done"

# check if CA's self-signed cert exists 
log "checking if CA self-signed cert exists..."

if ! test -f "$CERT_DIR/$CA_NAME.crt.pem"; then 
  log "  generating CA self-signed cert..."
  gen_self_signed_cert "$CA_NAME" "$CERT_DIR" "$CA_SUBJ" "$DAYS"
fi 

log "done"

# check if leaf keys exist
log "checking if leaf keys exist..."

if ! test -f "$CERT_DIR/$NAME.pvt.pem"; then 
  log "  generating leaf keys..."
  gen_keypair "$NAME" "$CERT_DIR"
fi

if ! test -f "$CERT_DIR/$NAME.pub.pem"; then 
  log "  generating leaf keys..."
  gen_keypair "$NAME" "$CERT_DIR"
fi

log "done"


# check if leaf certificate signing request exists
log "checking if certificate signing request exists..."
if ! test -f "$CERT_DIR/$NAME.csr.pem"; then 
  log "  generating certificate signing request..."
  gen_csr "$NAME" "$CERT_DIR" "$SUBJ" "$SUBJ_ALT_NAME"
fi

log "done"

# check if leaf certificate exists
log "checking if leaf certificate exists..."
if ! test -f "$CERT_DIR/$NAME.crt.pem"; then 
  log "  generating leaf certificate..."
  sign_csr "$NAME" "$CERT_DIR" "$CA_NAME" "$DAYS"
fi

log "done"
