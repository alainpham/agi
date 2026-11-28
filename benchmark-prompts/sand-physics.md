Build a self-contained "Falling Sand Physics Simulation" (cellular automata) inside a single, beautifully styled HTML file. The entire application must be written in vanilla HTML, CSS, and JavaScript with NO external libraries or dependencies. 

### Visual & UI Requirements:
1. UI Layout: A clean, modern, dark-themed dashboard. Center the simulation canvas. Provide a control panel on the side or top with styled buttons to select the active material, a "Clear Canvas" button, and a slider to adjust brush/drop size.
2. Canvas Dimensions: Fixed at 400x400 pixels The internal simulation grid should map to a resolution that ensures high performance : 100x100 grid cells mapped onto the 400x400 canvas.
3. Visuals: Elements must have distinct, vibrant colors:
   - Empty Space: Deep charcoal/black
   - Sand: Rich gold/yellow 
   - Water: Vibrant blue 
   - Wall (Impassable): Solid slate gray 
   - Acid: Glowing neon green

### Simulation Mechanics & Physics Rules:
You must implement a discrete 2D grid array state and update it using a strict frame-by-frame loop via `requestAnimationFrame`. The physics elements must interact according to these exact rules:
1. Wall: Static. Cannot move, fall, or be displaced.
2. Sand: Falls straight down into empty space. If the space directly below is blocked by Sand or Wall, it must attempt to slide diagonally down-left or down-right at random if those spaces are empty. If it falls into Water or Acid, it should sink through it (displace it upward).
3. Water: Falls straight down. If blocked below, it flows diagonally down-left or down-right. If those are blocked, it must spread out horizontally left or right into empty space until it hits a wall or another element.
4. Acid: Falls down and flows horizontally exactly like Water, but with a unique property: if it comes into direct contact with Sand or Wall (top, bottom, or sides), it "dissolves" both itself and one pixel of that material, turning both cells back into Empty Space.

### Critical Implementation Rules (The Coding Trap):
- Multi-Pass / Directional Processing: To prevent a single particle from "teleporting" from the top of the screen to the bottom in a single frame, you must iterate through the grid from the BOTTOM row up to the top row when processing movement rules.
- Horizontal Shuffling: When processing diagonal or horizontal movement, randomize whether the engine checks left or right first. If you do not randomize this, the liquids and sand will unnaturally pile up or skew heavily toward one side of the screen.
- Interaction: Implement smooth mouse dragging on the canvas so the user can "paint" streams of elements into the sandbox in real-time.

### Deliverable:
Write the complete, production-ready code inside a single HTML file containing the full HTML, CSS, and JavaScript It must work immediately when saved as an .html file and opened in a browser.
