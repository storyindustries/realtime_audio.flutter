package dev.volskaya.realtime_audio

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * `AudioManager.mode` / communication-device routing are PROCESS-GLOBAL while
 * engines are per-instance: without a ledger, engine B's exit() clobbers
 * engine A's in-call voice route (last-exit-wins — rev-lifecycle D2). The
 * ledger refcounts holds so only the FIRST hold configures and only the LAST
 * release restores.
 */
class CommSessionLedgerTest {

  @Test
  fun `first hold configures, last release restores`() {
    val ledger = CommSessionLedger()
    assertTrue(ledger.acquire(), "first hold must configure the comm session")
    assertTrue(ledger.release(), "last release must restore")
  }

  @Test
  fun `nested holds neither reconfigure nor restore early`() {
    val ledger = CommSessionLedger()
    assertTrue(ledger.acquire())
    assertFalse(ledger.acquire(), "second engine must not reconfigure")
    assertFalse(ledger.release(), "first release with another holder must not restore")
    assertTrue(ledger.release(), "the final holder's release restores")
  }

  @Test
  fun `unbalanced release is a no-op`() {
    val ledger = CommSessionLedger()
    assertFalse(ledger.release(), "release without a hold must not restore")
    assertTrue(ledger.acquire(), "ledger must stay usable after an unbalanced release")
  }
}
