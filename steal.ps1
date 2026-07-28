export default {
  async fetch(request) {
    if (request.method === "POST") {
      try {
        const data = await request.json();
        console.log("PC:", data.pc);
        console.log("User:", data.user);
        console.log("File length (base64):", data.file ? data.file.length : 0);
        console.log("First 100 chars of file:", data.file ? data.file.substring(0, 100) : "none");
        return new Response(JSON.stringify({ 
          status: "ok", 
          fileSize: data.file ? data.file.length : 0
        }), {
          headers: { "Content-Type": "application/json" }
        });
      } catch (e) {
        console.error("Error:", e.message);
        return new Response(JSON.stringify({ error: e.message }), { status: 400 });
      }
    }
    return new Response("Send POST with JSON data", { status: 200 });
  }
}
