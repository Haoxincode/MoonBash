// moon_bash FFI Layer
// Host bridges for side-effectful operations.

/// JS bridge: delegate fetch requests to `globalThis.__moon_bash_fetch`.
/// The bridge must return a JSON string.
#cfg(target="js")
extern "js" fn host_fetch_sync_js(request_json : String) -> String =
  #| function(requestJson) {
  #|   try {
  #|     const bridge = globalThis.__moon_bash_fetch;
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

/// JS bridge: delegate sleep requests to `globalThis.__moon_bash_sleep`.
/// The bridge returns an empty string on success or an error message.
#cfg(target="js")
extern "js" fn host_sleep_sync_js(duration_ms : Int) -> String =
  #| function(durationMs) {
  #|   try {
  #|     const bridge = globalThis.__moon_bash_sleep;
  #|     if (typeof bridge !== "function") {
  #|       return "timer sleep bridge is not configured";
  #|     }
  #|     const result = bridge(durationMs);
  #|     if (result && typeof result.then === "function") {
  #|       return "async sleep bridge is not supported by sync runtime";
  #|     }
  #|     if (typeof result === "string") {
  #|       return result;
  #|     }
  #|     if (typeof result === "undefined") {
  #|       return "";
  #|     }
  #|     return "";
  #|   } catch (error) {
  #|     return error && error.message ? error.message : String(error);
  #|   }
  #| }

#cfg(not(target="js"))
fn host_sleep_sync_js(_duration_ms : Int) -> String {
  "sleep is only supported on js target"
}

/// Sleep through host timer bridge.
pub fn sleep_sync(duration_ms : Int) -> String {
  host_sleep_sync_js(duration_ms)
}

/// JS bridge: read monotonic milliseconds from `globalThis.__moon_bash_now`.
#cfg(target="js")
extern "js" fn host_now_ms_sync_js() -> Int =
  #| function() {
  #|   try {
  #|     const bridge = globalThis.__moon_bash_now;
  #|     let value;
  #|     if (typeof bridge === "function") {
  #|       value = bridge();
  #|     } else if (typeof performance !== "undefined" && performance && typeof performance.now === "function") {
  #|       value = performance.now();
  #|     } else if (typeof Date !== "undefined" && typeof Date.now === "function") {
  #|       value = Date.now();
  #|     } else {
  #|       value = 0;
  #|     }
  #|     if (!Number.isFinite(value)) {
  #|       return 0;
  #|     }
  #|     if (value < 0) {
  #|       value = 0;
  #|     }
  #|     return Math.floor(value) % 2147483647;
  #|   } catch (_error) {
  #|     return 0;
  #|   }
  #| }

#cfg(not(target="js"))
fn host_now_ms_sync_js() -> Int {
  0
}

/// Return monotonic milliseconds from the host.
pub fn now_ms_sync() -> Int {
  host_now_ms_sync_js()
}

/// JS bridge: delegate VM execution requests to `globalThis.__moon_bash_vm`.
/// The bridge must return a JSON string.
#cfg(target="js")
extern "js" fn host_vm_sync_js(request_json : String) -> String =
  #| function(requestJson) {
  #|   try {
  #|     const bridge = globalThis.__moon_bash_vm;
  #|     if (typeof bridge !== "function") {
  #|       return JSON.stringify({
  #|         stdout: "",
  #|         stderr: "",
  #|         exitCode: 127,
  #|         error: "vm bridge is not configured",
  #|       });
  #|     }
  #|     const result = bridge(requestJson);
  #|     if (result && typeof result.then === "function") {
  #|       return JSON.stringify({
  #|         stdout: "",
  #|         stderr: "",
  #|         exitCode: 1,
  #|         error: "async vm bridge is not supported by sync runtime",
  #|       });
  #|     }
  #|     if (typeof result === "string") {
  #|       return result;
  #|     }
  #|     if (typeof result === "undefined") {
  #|       return JSON.stringify({
  #|         stdout: "",
  #|         stderr: "",
  #|         exitCode: 1,
  #|         error: "vm bridge returned undefined",
  #|       });
  #|     }
  #|     return JSON.stringify(result);
  #|   } catch (error) {
  #|     const message = error && error.message ? error.message : String(error);
  #|     return JSON.stringify({
  #|       stdout: "",
  #|       stderr: "",
  #|       exitCode: 1,
  #|       error: message,
  #|     });
  #|   }
  #| }

#cfg(not(target="js"))
fn host_vm_sync_js(_request_json : String) -> String {
  "{\"stdout\":\"\",\"stderr\":\"\",\"exitCode\":127,\"error\":\"vm bridge is only supported on js target\"}"
}

/// Perform one VM bridge call and return a JSON-encoded response payload.
pub fn vm_sync(request_json : String) -> String {
  host_vm_sync_js(request_json)
}

/// JS bridge: delegate custom command execution to `globalThis.__moon_bash_custom`.
/// The bridge must return a JSON string.
#cfg(target="js")
extern "js" fn host_custom_command_sync_js(request_json : String) -> String =
  #| function(requestJson) {
  #|   try {
  #|     const bridge = globalThis.__moon_bash_custom;
  #|     if (typeof bridge !== "function") {
  #|       return JSON.stringify({
  #|         handled: false,
  #|         stdout: "",
  #|         stderr: "",
  #|         exitCode: 127,
  #|       });
  #|     }
  #|     const result = bridge(requestJson);
  #|     if (result && typeof result.then === "function") {
  #|       return JSON.stringify({
  #|         handled: false,
  #|         stdout: "",
  #|         stderr: "",
  #|         exitCode: 1,
  #|         error: "async custom command bridge is not supported by sync runtime",
  #|       });
  #|     }
  #|     if (typeof result === "string") {
  #|       return result;
  #|     }
  #|     if (typeof result === "undefined") {
  #|       return JSON.stringify({
  #|         handled: false,
  #|         stdout: "",
  #|         stderr: "",
  #|         exitCode: 1,
  #|         error: "custom command bridge returned undefined",
  #|       });
  #|     }
  #|     return JSON.stringify(result);
  #|   } catch (error) {
  #|     const message = error && error.message ? error.message : String(error);
  #|     return JSON.stringify({
  #|       handled: false,
  #|       stdout: "",
  #|       stderr: "",
  #|       exitCode: 1,
  #|       error: message,
  #|     });
  #|   }
  #| }

#cfg(not(target="js"))
fn host_custom_command_sync_js(_request_json : String) -> String {
  "{\"handled\":false,\"stdout\":\"\",\"stderr\":\"\",\"exitCode\":127,\"error\":\"custom command bridge is only supported on js target\"}"
}

/// Perform one custom command bridge call and return a JSON payload.
pub fn custom_command_sync(request_json : String) -> String {
  host_custom_command_sync_js(request_json)
}
