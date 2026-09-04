
package ch.ethz.ssh2;

import java.io.IOException;

/**
 * Minimal bundled Ganymed adapter that enforces strict, pinned SSH server host-key
 * trust for the pseudo-CT MLSC runtime transport.
 * <p>
 * This adapter is required because the bundled transport must hand a real Java
 * {@link ServerHostKeyVerifier} to {@link Connection#connect(ServerHostKeyVerifier)}
 * before authentication, and the supported MATLAB baseline cannot supply one from a
 * MATLAB function. The verifier is intentionally fail-closed: it accepts a presented
 * server host key only when <em>all</em> of the following hold:
 * <ul>
 *   <li>the connecting hostname equals the pinned hostname,</li>
 *   <li>the connecting TCP port equals the pinned port, and</li>
 *   <li>the in-memory {@link KnownHosts} database reports the key as
 *       {@link KnownHosts#HOSTKEY_IS_OK}.</li>
 * </ul>
 * A new key, a changed key, a key that matches a different host, an unsupported host
 * key algorithm, or a key blob that cannot be parsed all resolve to {@code false}, which
 * makes {@code KexManager} abort the handshake with an IOException before any
 * authentication, account discovery, or job submission is attempted.
 * <p>
 * The database is supplied as in-memory material only. This class never writes, reads,
 * mutates, caches, or logs host-key material, and it never performs first-use trust or
 * auto-add.
 */
public class MLSCStrictHostKeyVerifier implements ServerHostKeyVerifier
{
	private final KnownHosts known_hosts;
	private final String pinned_hostname;
	private final int pinned_port;

	/**
	 * @param known_hosts an in-memory database pre-populated with independently trusted
	 *        host-key material; must not be null.
	 * @param pinned_hostname the exact hostname the MLSC transport is connecting to;
	 *        must be non-empty.
	 * @param pinned_port the exact TCP port the MLSC transport is connecting to.
	 */
	public MLSCStrictHostKeyVerifier(KnownHosts known_hosts, String pinned_hostname, int pinned_port)
	{
		if (known_hosts == null)
			throw new IllegalArgumentException("known_hosts may not be null");

		if (pinned_hostname == null || pinned_hostname.length() == 0)
			throw new IllegalArgumentException("pinned_hostname may not be empty");

		this.known_hosts = known_hosts;
		this.pinned_hostname = pinned_hostname.toLowerCase();
		this.pinned_port = pinned_port;
	}

	public boolean verifyServerHostKey(String hostname, int port, String serverHostKeyAlgorithm, byte[] serverHostKey)
			throws IOException
	{
		// Fail closed on any host/port that is not the exact pinned target.
		if (hostname == null || port != pinned_port)
			return false;

		if (hostname.toLowerCase().equals(pinned_hostname) == false)
			return false;

		// Fail closed on an unsupported algorithm or an unparseable key blob, and accept
		// the key only when the trusted in-memory database reports HOSTKEY_IS_OK (never
		// HOSTKEY_IS_NEW or HOSTKEY_HAS_CHANGED).
		int status;

		try
		{
			status = known_hosts.verifyHostkey(hostname, serverHostKeyAlgorithm, serverHostKey);
		}
		catch (Exception e)
		{
			return false;
		}

		return status == KnownHosts.HOSTKEY_IS_OK;
	}
}
