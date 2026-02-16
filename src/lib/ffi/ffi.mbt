// MoonBash FFI Layer
// Host bridges for side-effectful operations.

/// JS bridge: delegate fetch requests to `globalThis.__moonbash_fetch`.
/// The bridge must return a JSON string.
#cfg(target="js")
extern "js" fn host_fetch_sync_js(request_json : String) -> String =
  #| function(requestJson) {
  #|   try {
  #|     const bridge = globalThis.__moonbash_fetch;
  #|     if (typeof bridge !== "function") {
  #|       return JSON.stringify({
  #|         ok: false,
  #|         status: 0,
  #|         statusText: "",
  #|         headers: {},
  #|         body: "",
  #|         error: "network fetch bridge is not configured",
  #|       });
  #|     }
  #|     const result = bridge(requestJson);
  #|     if (result && typeof result.then === "function") {
  #|       return JSON.stringify({
  #|         ok: false,
  #|         status: 0,
  #|         statusText: "",
  #|         headers: {},
  #|         body: "",
  #|         error: "async fetch bridge is not supported by sync runtime",
  #|       });
  #|     }
  #|     if (typeof result === "string") {
  #|       return result;
  #|     }
  #|     if (typeof result === "undefined") {
  #|       return JSON.stringify({
  #|         ok: false,
  #|         status: 0,
  #|         statusText: "",
  #|         headers: {},
  #|         body: "",
  #|         error: "fetch bridge returned undefined",
  #|       });
  #|     }
  #|     return JSON.stringify(result);
  #|   } catch (error) {
  #|     const message = error && error.message ? error.message : String(error);
  #|     return JSON.stringify({
  #|       ok: false,
  #|       status: 0,
  #|       statusText: "",
  #|       headers: {},
  #|       body: "",
  #|       error: message,
  #|     });
  #|   }
  #| }

#cfg(not(target="js"))
fn host_fetch_sync_js(_request_json : String) -> String {
  "{\"ok\":false,\"status\":0,\"statusText\":\"\",\"headers\":{},\"body\":\"\",\"error\":\"network fetch is only supported on js target\"}"
}

/// Perform one fetch bridge call and return a JSON-encoded response payload.
pub fn fetch_sync(request_json : String) -> String {
  host_fetch_sync_js(request_json)
}
