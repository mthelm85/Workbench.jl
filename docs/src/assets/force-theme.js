// Force the default Documenter theme (documenter-dark) on every load.
// The custom CSS is designed for a single look — stale localStorage picks
// from the (now-hidden) settings cog would break it.
if (typeof window.localStorage !== "undefined") {
    window.localStorage.removeItem("documenter-theme");
}
