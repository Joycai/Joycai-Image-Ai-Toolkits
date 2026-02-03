# Joycai Image AI Toolkits - MCP Server Guide

This guide explains how to set up and use the Model Context Protocol (MCP) server feature in **Joycai Image AI Toolkits**. This feature allows external applications and MCP-compatible clients (like Claude Desktop or other AI assistants) to interact with the toolkit programmatically.

## What is MCP?

The **Model Context Protocol (MCP)** is an open standard that enables AI models to interact with external tools and data. By enabling the MCP server in this app, you expose specific functionalities (like listing gallery images or generating new images) as "tools" that can be called by other software.

## enabling the MCP Server

1.  **Open the App**: Launch Joycai Image AI Toolkits.
2.  **Go to Settings**: Click on the **Settings** icon in the navigation rail.
3.  **Scroll to MCP Server Settings**: Locate the section titled "MCP Server Settings".
4.  **Enable Server**: Toggle the switch for "Enable MCP Server".
5.  **Configure Port**: Enter a valid port number (default is `3000`). Ensure this port is not used by other applications.
6.  **Restart**: The server starts automatically when enabled. If you change the port, toggle the switch off and on again to restart with the new configuration.

## Connecting to the Server

The server runs locally on your machine.

*   **Base URL**: `http://localhost:<PORT>` (e.g., `http://localhost:3000`)
*   **SSE Endpoint**: `http://localhost:<PORT>/sse`
*   **Messages Endpoint**: `http://localhost:<PORT>/messages`

### Using with Claude Desktop (Example)

To use this toolkit as a tool for Claude Desktop:

1.  Open your Claude Desktop configuration file (`claude_desktop_config.json`).
    *   **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
    *   **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
2.  Add the following configuration under `mcpServers`:

```json
{
  "mcpServers": {
    "joycai-toolkit": {
      "command": "node", 
      "args": ["path/to/proxy/script.js"], 
      "env": {}
    }
  }
}
```

*Note: Direct SSE connection support in some clients might vary. For clients that require a stdio-based transport (executing a command), you may need a small proxy script that connects to this app's SSE endpoint.*

### Direct API Interaction

You can interact with the server using standard HTTP requests if you are building a custom integration.

#### 1. Initialize
Send a request to check capabilities (standard JSON-RPC 2.0 format).

**Request:**
`POST /messages`
```json
{
  "jsonrpc": "2.0",
  "method": "initialize",
  "params": {
    "protocolVersion": "0.1.0",
    "capabilities": {},
    "clientInfo": {"name": "client", "version": "1.0"}
  },
  "id": 1
}
```

#### 2. List Tools
Discover what the toolkit can do.

**Request:**
`POST /messages`
```json
{
  "jsonrpc": "2.0",
  "method": "tools/list",
  "params": {},
  "id": 2
}
```

**Expected Response (Example):**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "tools": [
      {
        "name": "list_gallery_images",
        "description": "Get a list of images in the source gallery",
        "inputSchema": { ... }
      }
    ]
  },
  "id": 2
}
```

#### 3. Call a Tool
Execute a function, such as listing images.

**Request:**
`POST /messages`
```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "list_gallery_images",
    "arguments": {}
  },
  "id": 3
}
```

## Security Note

The MCP server binds to `localhost` (127.0.0.1). It is designed for local interactions. **Do not** expose this port to the public internet, as it allows access to your local files configured in the app without authentication.
