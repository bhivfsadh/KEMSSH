#include "includes.h"

#include <sys/types.h>

#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

#include "digest.h"
#include "hmac.h"
#include "kex.h"
#include "openbsd-compat/base64.h"
#include "packet.h"
#include "sshbuf.h"
#include "sshkey.h"
#include "ssh2.h"
#include "ssherr.h"
#include "ssh-kem.h"
#include "xmalloc.h"

#include "oqs/oqs.h"

struct sshkem {
	const char *name;
	OQS_KEM *oqs;
};

struct ssh_kem_identity {
	char *alg;
	u_char *public_key;
	size_t public_key_len;
	u_char *secret_key;
	size_t secret_key_len;
};

static void
ssh_kem_trim(char *line)
{
	char *end;

	while (isspace((u_char)*line))
		line++;
	end = line + strlen(line);
	while (end > line && isspace((u_char)end[-1]))
		*--end = '\0';
}

static int
ssh_kem_has_suffix(const char *name, const char *suffix)
{
	size_t name_len, suffix_len;

	if (name == NULL || suffix == NULL)
		return 0;
	name_len = strlen(name);
	suffix_len = strlen(suffix);
	if (name_len < suffix_len)
		return 0;
	return strcasecmp(name + name_len - suffix_len, suffix) == 0;
}

const char *
ssh_kem_normalize_name(const char *name)
{
	char buf[64];
	size_t len;

	if (name == NULL)
		return NULL;
	if (strlcpy(buf, name, sizeof(buf)) >= sizeof(buf))
		return NULL;
	if (ssh_kem_has_suffix(buf, "-sha256")) {
		len = strlen(buf) - (sizeof("-sha256") - 1);
		buf[len] = '\0';
	}
	if (strcasecmp(buf, SSH_KEM_ALG_MLKEM512) == 0 ||
	    strcasecmp(buf, "ML-KEM-512") == 0 ||
	    strcasecmp(buf, "kyber512") == 0 ||
	    strcasecmp(buf, "Kyber512") == 0)
		return SSH_KEM_ALG_MLKEM512;
	if (strcasecmp(buf, SSH_KEM_DEFAULT_ALG) == 0 ||
	    strcasecmp(buf, "ML-KEM-768") == 0 ||
	    strcasecmp(buf, "kyber768") == 0 ||
	    strcasecmp(buf, "Kyber768") == 0)
		return SSH_KEM_DEFAULT_ALG;
	if (strcasecmp(buf, SSH_KEM_ALG_MLKEM1024) == 0 ||
	    strcasecmp(buf, "ML-KEM-1024") == 0 ||
	    strcasecmp(buf, "kyber1024") == 0 ||
	    strcasecmp(buf, "Kyber1024") == 0)
		return SSH_KEM_ALG_MLKEM1024;
	return NULL;
}

int
ssh_kem_name_equal(const char *left, const char *right)
{
	const char *left_normalized, *right_normalized;

	left_normalized = ssh_kem_normalize_name(left);
	right_normalized = ssh_kem_normalize_name(right);
	if (left_normalized == NULL || right_normalized == NULL)
		return 0;
	return strcmp(left_normalized, right_normalized) == 0;
}

int
ssh_kem_response_digest(const char *name)
{
	if (ssh_kem_normalize_name(name) == NULL)
		return -1;
	return SSH_DIGEST_SHA256;
}

size_t
ssh_kem_response_len(const char *name)
{
	int digest_alg;

	if ((digest_alg = ssh_kem_response_digest(name)) == -1)
		return 0;
	return ssh_hmac_bytes(digest_alg);
}

static struct sshkem *
ssh_kem_from_name(const char *name)
{
	struct sshkem *kem;

	if (name == NULL)
		return NULL;
	kem = xcalloc(1, sizeof(*kem));
	if (strcmp(name, SSH_KEM_ALG_MLKEM512) == 0)
		kem->oqs = OQS_KEM_new(OQS_KEM_alg_ml_kem_512);
	else if (strcmp(name, SSH_KEM_DEFAULT_ALG) == 0)
		kem->oqs = OQS_KEM_new(OQS_KEM_alg_ml_kem_768);
	else if (strcmp(name, SSH_KEM_ALG_MLKEM1024) == 0)
		kem->oqs = OQS_KEM_new(OQS_KEM_alg_ml_kem_1024);
	if (kem->oqs == NULL) {
		free(kem);
		return NULL;
	}
	kem->name = name;
	return kem;
}

struct sshkem *
ssh_kem_new(const char *name)
{
	return ssh_kem_from_name(ssh_kem_normalize_name(name));
}

void
ssh_kem_free(struct sshkem *kem)
{
	if (kem == NULL)
		return;
	OQS_KEM_free(kem->oqs);
	free(kem);
}

size_t
ssh_kem_public_key_len(struct sshkem *kem)
{
	return kem != NULL && kem->oqs != NULL ? kem->oqs->length_public_key : 0;
}

size_t
ssh_kem_secret_key_len(struct sshkem *kem)
{
	return kem != NULL && kem->oqs != NULL ? kem->oqs->length_secret_key : 0;
}

size_t
ssh_kem_ciphertext_len(struct sshkem *kem)
{
	return kem != NULL && kem->oqs != NULL ? kem->oqs->length_ciphertext : 0;
}

size_t
ssh_kem_shared_secret_len(struct sshkem *kem)
{
	return kem != NULL && kem->oqs != NULL ? kem->oqs->length_shared_secret : 0;
}

int
ssh_kem_keypair(struct sshkem *kem, u_char *public_key, u_char *secret_key)
{
	if (kem == NULL || kem->oqs == NULL || public_key == NULL ||
	    secret_key == NULL)
		return SSH_ERR_INVALID_ARGUMENT;
	return OQS_KEM_keypair(kem->oqs, public_key, secret_key) == OQS_SUCCESS ?
	    0 : SSH_ERR_LIBCRYPTO_ERROR;
}

int
ssh_kem_encaps(struct sshkem *kem, u_char *ciphertext,
    u_char *shared_secret, const u_char *public_key)
{
	if (kem == NULL || kem->oqs == NULL || ciphertext == NULL ||
	    shared_secret == NULL || public_key == NULL)
		return SSH_ERR_INVALID_ARGUMENT;
	return OQS_KEM_encaps(kem->oqs, ciphertext, shared_secret,
	    public_key) == OQS_SUCCESS ? 0 : SSH_ERR_LIBCRYPTO_ERROR;
}

int
ssh_kem_decaps(struct sshkem *kem, u_char *shared_secret,
    const u_char *ciphertext, const u_char *secret_key)
{
	if (kem == NULL || kem->oqs == NULL || shared_secret == NULL ||
	    ciphertext == NULL || secret_key == NULL)
		return SSH_ERR_INVALID_ARGUMENT;
	return OQS_KEM_decaps(kem->oqs, shared_secret, ciphertext,
	    secret_key) == OQS_SUCCESS ? 0 : SSH_ERR_LIBCRYPTO_ERROR;
}

int
ssh_kem_name_permitted(const char *allowlist, const char *name)
{
	char *cp, *list, *item;
	const char *normalized;
	int allowed = 0;

	if ((normalized = ssh_kem_normalize_name(name)) == NULL ||
	    allowlist == NULL)
		return 0;
	list = xstrdup(allowlist);
	for (cp = list; (item = strsep(&cp, ",")) != NULL;) {
		const char *candidate;

		if ((candidate = ssh_kem_normalize_name(item)) == NULL)
			continue;
		if (strcmp(candidate, normalized) == 0) {
			allowed = 1;
			break;
		}
	}
	free(list);
	return allowed;
}

int
ssh_kem_names_valid(const char *names)
{
	char *cp, *list, *item;
	int ret = 0;

	if (names == NULL || *names == '\0')
		return 0;
	list = xstrdup(names);
	for (cp = list; (item = strsep(&cp, ",")) != NULL;) {
		if (ssh_kem_normalize_name(item) == NULL)
			goto out;
	}
	ret = 1;
out:
	free(list);
	return ret;
}

char *
ssh_kem_first_alg(const char *names)
{
	char *ret, *cp;

	if (!ssh_kem_names_valid(names))
		return NULL;
	ret = xstrdup(names);
	if ((cp = strchr(ret, ',')) != NULL)
		*cp = '\0';
	return ret;
}

int
ssh_kem_b64_encode(const u_char *data, size_t len, char **out)
{
	size_t outlen;
	char *encoded;
	int n;

	if (out != NULL)
		*out = NULL;
	if (data == NULL || out == NULL)
		return SSH_ERR_INVALID_ARGUMENT;
	outlen = ((len + 2) / 3) * 4 + 1;
	encoded = xcalloc(outlen, sizeof(*encoded));
	if ((n = b64_ntop(data, len, encoded, outlen)) == -1) {
		free(encoded);
		return SSH_ERR_INVALID_FORMAT;
	}
	encoded[n] = '\0';
	*out = encoded;
	return 0;
}

int
ssh_kem_b64_decode(const char *input, u_char **data, size_t *len)
{
	size_t maxlen;
	u_char *decoded;
	int n;

	if (data != NULL)
		*data = NULL;
	if (len != NULL)
		*len = 0;
	if (input == NULL || data == NULL)
		return SSH_ERR_INVALID_ARGUMENT;
	maxlen = strlen(input) * 3 / 4 + 4;
	decoded = xcalloc(maxlen, sizeof(*decoded));
	if ((n = b64_pton(input, decoded, maxlen)) == -1) {
		free(decoded);
		return SSH_ERR_INVALID_FORMAT;
	}
	*data = decoded;
	if (len != NULL)
		*len = (size_t)n;
	return 0;
}

static int
ssh_kem_identity_validate(struct ssh_kem_identity *identity)
{
	struct sshkem *kem;
	int ret = SSH_ERR_INVALID_FORMAT;

	if (identity == NULL || identity->alg == NULL ||
	    identity->public_key == NULL || identity->secret_key == NULL)
		return SSH_ERR_INVALID_FORMAT;
	if ((kem = ssh_kem_new(identity->alg)) == NULL)
		return SSH_ERR_INVALID_FORMAT;
	if (identity->public_key_len != ssh_kem_public_key_len(kem) ||
	    identity->secret_key_len != ssh_kem_secret_key_len(kem))
		goto out;
	ret = 0;
out:
	ssh_kem_free(kem);
	return ret;
}

int
ssh_kem_load_identity(const char *path, struct ssh_kem_identity **idp)
{
	FILE *f = NULL;
	char *line = NULL, *cp, *key, *value;
	size_t linesize = 0;
	struct ssh_kem_identity *identity = NULL;
	int ret = SSH_ERR_INVALID_FORMAT;

	if (idp != NULL)
		*idp = NULL;
	if (path == NULL || idp == NULL)
		return SSH_ERR_INVALID_ARGUMENT;
	if ((f = fopen(path, "r")) == NULL)
		return SSH_ERR_SYSTEM_ERROR;
	identity = xcalloc(1, sizeof(*identity));
	while (getline(&line, &linesize, f) != -1) {
		cp = line;
		while (isspace((u_char)*cp))
			cp++;
		if (*cp == '\0' || *cp == '#' || *cp == '\n')
			continue;
		key = strsep(&cp, " \t=\r\n");
		if (key == NULL || cp == NULL)
			goto out;
		while (isspace((u_char)*cp) || *cp == '=')
			cp++;
		ssh_kem_trim(cp);
		value = cp;
		if (*value == '\0')
			goto out;
		if (strcasecmp(key, "algorithm") == 0) {
			const char *normalized;

			if ((normalized = ssh_kem_normalize_name(value)) == NULL)
				goto out;
			free(identity->alg);
			identity->alg = xstrdup(normalized);
		} else if (strcasecmp(key, "public") == 0) {
			free(identity->public_key);
			identity->public_key = NULL;
			identity->public_key_len = 0;
			if ((ret = ssh_kem_b64_decode(value, &identity->public_key,
			    &identity->public_key_len)) != 0)
				goto out;
		} else if (strcasecmp(key, "secret") == 0) {
			freezero(identity->secret_key, identity->secret_key_len);
			identity->secret_key = NULL;
			identity->secret_key_len = 0;
			if ((ret = ssh_kem_b64_decode(value, &identity->secret_key,
			    &identity->secret_key_len)) != 0)
				goto out;
		}
	}
	if ((ret = ssh_kem_identity_validate(identity)) != 0)
		goto out;
	*idp = identity;
	identity = NULL;
	ret = 0;
out:
	if (f != NULL)
		fclose(f);
	free(line);
	ssh_kem_identity_free(identity);
	return ret;
}

void
ssh_kem_identity_free(struct ssh_kem_identity *identity)
{
	if (identity == NULL)
		return;
	free(identity->alg);
	free(identity->public_key);
	freezero(identity->secret_key, identity->secret_key_len);
	freezero(identity, sizeof(*identity));
}

const char *
ssh_kem_identity_alg(const struct ssh_kem_identity *identity)
{
	return identity != NULL ? identity->alg : NULL;
}

const u_char *
ssh_kem_identity_public_key(const struct ssh_kem_identity *identity,
    size_t *lenp)
{
	if (lenp != NULL)
		*lenp = identity != NULL ? identity->public_key_len : 0;
	return identity != NULL ? identity->public_key : NULL;
}

const u_char *
ssh_kem_identity_secret_key(const struct ssh_kem_identity *identity,
    size_t *lenp)
{
	if (lenp != NULL)
		*lenp = identity != NULL ? identity->secret_key_len : 0;
	return identity != NULL ? identity->secret_key : NULL;
}

int
ssh_kem_derive_response(struct ssh *ssh, const char *user,
	const char *service, const char *method, const char *alg,
    const u_char *public_key,
    size_t public_key_len, const u_char *ciphertext, size_t ciphertext_len,
    const u_char *shared_secret, size_t shared_secret_len, u_char *response,
    size_t response_len)
{
	struct sshbuf *context = NULL;
	struct ssh_hmac_ctx *hmac = NULL;
	size_t digest_len;
	int digest_alg;
	int r = SSH_ERR_INTERNAL_ERROR;

	if (ssh == NULL || ssh->kex == NULL || ssh->kex->session_id == NULL ||
	    user == NULL || service == NULL || method == NULL || alg == NULL ||
	    public_key == NULL ||
	    ciphertext == NULL || shared_secret == NULL || response == NULL)
		return SSH_ERR_INVALID_ARGUMENT;
	if ((digest_alg = ssh_kem_response_digest(alg)) == -1)
		return SSH_ERR_INVALID_ARGUMENT;
	digest_len = ssh_hmac_bytes(digest_alg);
	if (response_len < digest_len)
		return SSH_ERR_INVALID_ARGUMENT;
	if ((context = sshbuf_new()) == NULL)
		return SSH_ERR_ALLOC_FAIL;
	if ((r = sshbuf_put_u8(context, SSH2_MSG_USERAUTH_REQUEST)) != 0 ||
	    (r = sshbuf_put_cstring(context, user)) != 0 ||
	    (r = sshbuf_put_cstring(context, service)) != 0 ||
	    (r = sshbuf_put_cstring(context, method)) != 0 ||
	    (r = sshbuf_put_cstring(context, alg)) != 0 ||
	    (r = sshbuf_put_string(context, public_key, public_key_len)) != 0 ||
	    (r = sshbuf_put_u8(context, SSH2_MSG_USERAUTH_KEM_CHALLENGE)) != 0 ||
	    (r = sshbuf_put_cstring(context, alg)) != 0 ||
	    (r = sshbuf_put_string(context, public_key, public_key_len)) != 0 ||
	    (r = sshbuf_put_string(context, ciphertext, ciphertext_len)) != 0)
		goto out;
	if ((hmac = ssh_hmac_start(digest_alg)) == NULL) {
		r = SSH_ERR_ALLOC_FAIL;
		goto out;
	}
	if ((r = ssh_hmac_init(hmac, shared_secret, shared_secret_len)) != 0 ||
	    (r = ssh_hmac_update_buffer(hmac, context)) != 0 ||
	    (r = ssh_hmac_update(hmac, sshbuf_ptr(ssh->kex->session_id),
	    sshbuf_len(ssh->kex->session_id))) != 0 ||
	    (r = ssh_hmac_final(hmac, response,
	    digest_len)) != 0)
		goto out;
	r = 0;
out:
	ssh_hmac_free(hmac);
	sshbuf_free(context);
	return r;
}