# Authentication

## When to Activate

Use when implementing login, API access, or session lifecycle—or after security reviews and breach readiness exercises. Apply for new clients, token formats, or MFA rollouts.

## Process

1. **Standards**: Prefer **OAuth 2.1** / **OpenID Connect** for delegated access; use certified libraries (**openid-client** Node, **AppAuth** mobile). Avoid custom crypto protocols.
2. **Passwords**: Hash with **Argon2id** (preferred) or **bcrypt** with per-user salt and adequate cost. Enforce breach-checked passwords (Have I Been Pwned k-anonymity API optional).
3. **Tokens**: Use signed JWTs with `exp`, `aud`, `iss`, and `jti`; bind to client where useful (DPoP or mTLS for high assurance). Store refresh tokens hashed server-side with rotation on use.
4. **Keys**: Rotate signing keys with `kid` in JWKS; support overlapping validity. Automate with **AWS KMS**, **HashiCorp Vault**, or cloud HSM.
5. **MFA**: Offer TOTP and WebAuthn; require step-up for sensitive actions. Backup codes stored hashed.
6. **Threat logging**: Log failed attempts with rate limits; avoid logging raw passwords or tokens. Alert on credential stuffing patterns.
7. **Revocation**: Maintain denylist or session version for compromised refresh tokens. Test revocation end-to-end in staging.

## Checklist

- [ ] OIDC/OAuth flows use vetted libraries
- [ ] Password hashing meets modern guidance
- [ ] JWT claims include aud/iss/exp; keys rotatable
- [ ] MFA available or enforced per risk
- [ ] Auth failures observable without secret leakage
- [ ] Revocation and rotation tested

## Tips

Use **PKCE** for all public clients. Prefer **HttpOnly**, `Secure`, `SameSite` cookies for browser sessions when first-party. Run **`nmap`/`sslyze`**-level TLS configs via platform defaults.
