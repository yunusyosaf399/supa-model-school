// DB12: retired. Owner accounts are now created with credentials directly.
// This endpoint intentionally cannot send emails or create Auth users.
Deno.serve((_request: Request) =>
  new Response(JSON.stringify({error:"Invitation flow retired. Update your app."}),{
    status:410,
    headers:{"Content-Type":"application/json","Cache-Control":"no-store"},
  }));
