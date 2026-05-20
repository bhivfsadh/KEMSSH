#ifndef SSH_KEM_H
#define SSH_KEM_H

#include <sys/types.h>

struct sshkem;
struct ssh_kem_identity;

#define SSH_KEM_AUTH_METHOD "publickey-kem"
#define SSH_KEM_AND_AUTH_METHOD "publickey-kem-and"
#define SSH_KEM_DEFAULT_ALG "mlkem768"
#define SSH_KEM_ALG_MLKEM512 "mlkem512"
#define SSH_KEM_ALG_MLKEM1024 "mlkem1024"

struct sshkem *ssh_kem_new(const char *name);
void ssh_kem_free(struct sshkem *kem);
size_t ssh_kem_public_key_len(struct sshkem *kem);
size_t ssh_kem_secret_key_len(struct sshkem *kem);
size_t ssh_kem_ciphertext_len(struct sshkem *kem);
size_t ssh_kem_shared_secret_len(struct sshkem *kem);
int ssh_kem_keypair(struct sshkem *kem, u_char *public_key,
    u_char *secret_key);
int ssh_kem_encaps(struct sshkem *kem, u_char *ciphertext,
    u_char *shared_secret, const u_char *public_key);
int ssh_kem_decaps(struct sshkem *kem, u_char *shared_secret,
    const u_char *ciphertext, const u_char *secret_key);
const char *ssh_kem_normalize_name(const char *name);
int ssh_kem_name_equal(const char *left, const char *right);
int ssh_kem_response_digest(const char *name);
size_t ssh_kem_response_len(const char *name);
int ssh_kem_names_valid(const char *names);
int ssh_kem_name_permitted(const char *allowlist, const char *name);
char *ssh_kem_first_alg(const char *names);
int ssh_kem_b64_encode(const u_char *data, size_t len, char **out);
int ssh_kem_b64_decode(const char *input, u_char **data, size_t *len);
int ssh_kem_load_identity(const char *path, struct ssh_kem_identity **idp);
void ssh_kem_identity_free(struct ssh_kem_identity *identity);
const char *ssh_kem_identity_alg(const struct ssh_kem_identity *identity);
const u_char *ssh_kem_identity_public_key(const struct ssh_kem_identity *identity,
    size_t *lenp);
const u_char *ssh_kem_identity_secret_key(const struct ssh_kem_identity *identity,
    size_t *lenp);
int ssh_kem_derive_response(struct ssh *ssh, const char *user,
    const char *service, const char *method, const char *alg,
    const u_char *public_key,
    size_t public_key_len, const u_char *ciphertext, size_t ciphertext_len,
    const u_char *shared_secret, size_t shared_secret_len, u_char *response,
    size_t response_len);

#endif