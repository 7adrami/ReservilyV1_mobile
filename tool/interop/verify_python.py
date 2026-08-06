"""Python half of the Dart<->Python interop fixture.

Verifies the Dart port matches the same primitives WebCrypto uses:
P-256 ECDH, HKDF-SHA256, AES-256-GCM, PBKDF2-SHA256. Then produces return
fixtures (a Python-generated identity + ciphertext) for Dart to decode.
"""
import base64
import hashlib
import hmac
import json
import sys

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

FIXTURE = sys.argv[1]
OUT = sys.argv[2]

with open(FIXTURE, "r", encoding="utf-8") as fh:
    f = json.load(fh)


def int_to_bytes(n):
    return n.to_bytes(32, "big")  # WebCrypto JWK pads coordinates to 32 bytes


def b64u_bytes(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def b64(s):
    return base64.b64decode(s)


def b64u(s):
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def spki_der(pem):
    return serialization.load_der_public_key(base64.b64decode(pem))


def jwk_to_priv(jwk):
    d = int.from_bytes(b64u(jwk["d"]), "big")
    return ec.derive_private_key(d, ec.SECP256R1())


def derive_key(priv, pub_spki):
    shared = priv.exchange(ec.ECDH(), spki_der(pub_spki))
    return HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=f["salt"].encode(),
        info=b"reservily-chat-v1",
    ).derive(shared)


# 1) Import Dart-generated identities and derive the shared conversation key.
alice_pub = spki_der(f["alice_pub_spki"])
bob_priv = jwk_to_priv(f["bob_priv_jwk"])
key = derive_key(bob_priv, f["alice_pub_spki"])

# 2) Decrypt the Dart payload.
payload_plain = AESGCM(key).decrypt(
    b64(f["dart_payload_nonce"]), b64(f["dart_payload_ct"]), None
)
payload = json.loads(payload_plain)
assert payload["t"] == "text", payload
assert payload["text"] == f["text"], payload

# 3) Decrypt the media blob with the per-file key.
media_plain = AESGCM(b64(f["media_key"])).decrypt(
    b64(f["media_iv"]), b64(f["media_ct"]), None
)
assert base64.b64encode(media_plain).decode() == f["media_plain"]

# 4) Unwrap the password vault (PBKDF2 + AES-GCM).
pbkdf = PBKDF2HMAC(
    algorithm=hashes.SHA256(),
    length=32,
    salt=b64(f["vault_salt"]),
    iterations=f.get("iterations", 150000),
)
kek = pbkdf.derive(f["vault_password"].encode())
wrapped = AESGCM(kek).decrypt(
    b64(f["vault_iv"]), b64(f["vault_ct"]), None
)
identity = json.loads(wrapped)
assert identity["pub"] == f["alice_pub_spki"], identity
assert identity["priv"]["d"] == f["alice_priv_jwk"]["d"], identity
assert identity["priv"]["x"] == f["alice_priv_jwk"]["x"], identity
assert identity["priv"]["y"] == f["alice_priv_jwk"]["y"], identity
assert identity["priv"]["kty"] == "EC" and identity["priv"]["crv"] == "P-256"

# 5) Produce return fixtures: a Python-generated identity + encrypted payload,
#    media and vault that Dart must decode.
py_bob = ec.generate_private_key(ec.SECP256R1())
py_pub_spki = base64.b64encode(
    py_bob.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
).decode()
pub = py_bob.public_key().public_numbers()
d = py_bob.private_numbers().private_value
py_jwk = {
    "kty": "EC",
    "crv": "P-256",
    "x": b64u_bytes(int_to_bytes(pub.x)),
    "y": b64u_bytes(int_to_bytes(pub.y)),
    "d": b64u_bytes(int_to_bytes(d)),
}

py_key = derive_key(py_bob, f["alice_pub_spki"])
py_nonce = b"py-nonce-001"  # 12 bytes
py_ct = AESGCM(py_key).encrypt(
    py_nonce, json.dumps({"t": "text", "text": "Hello from Python"}).encode(), None
)

py_media_key = b"m" * 32
py_media_iv = b"py-media-iv1"  # 12 bytes
py_media_plain = b"python-media-bytes-2026"
py_media_ct = AESGCM(py_media_key).encrypt(py_media_iv, py_media_plain, None)

py_vault_password = "python vault secret 42"
py_vault_salt = b"py-salt-16-bytes"[:16]
pbkdf2 = PBKDF2HMAC(hashes.SHA256(), 32, py_vault_salt, 150000)
py_kek = pbkdf2.derive(py_vault_password.encode())
py_vault_iv = b"py-vault-iv-1"  # 12 bytes
py_vault_ct = AESGCM(py_kek).encrypt(py_vault_iv, json.dumps(py_jwk).encode(), None)

out = {
    "py_pub_spki": py_pub_spki,
    "py_priv_jwk": py_jwk,
    "py_key_b64": base64.b64encode(py_key).decode(),
    "py_payload_ct": base64.b64encode(py_ct).decode(),
    "py_payload_nonce": base64.b64encode(py_nonce).decode(),
    "py_media_key": base64.b64encode(py_media_key).decode(),
    "py_media_iv": base64.b64encode(py_media_iv).decode(),
    "py_media_ct": base64.b64encode(py_media_ct).decode(),
    "py_vault_salt": base64.b64encode(py_vault_salt).decode(),
    "py_vault_iv": base64.b64encode(py_vault_iv).decode(),
    "py_vault_ct": base64.b64encode(py_vault_ct).decode(),
    "py_vault_password": py_vault_password,
}
with open(OUT, "w", encoding="utf-8") as fh:
    json.dump(out, fh, indent=2)
print("PYTHON INTEROP PASS")
print("payload length ok: " + str(len(payload["text"])))
