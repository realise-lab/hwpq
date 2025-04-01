from manim import *
import math
import numpy as np
import os

# Configure Manim
config.pixel_height = 1080
config.pixel_width = 1920
config.frame_rate = 30

class RegisterTreeAnimation(Scene):
    def __init__(self, queue_size=15, data_width=16, **kwargs):
        super().__init__(**kwargs)
        self.QUEUE_SIZE = queue_size
        self.DATA_WIDTH = data_width
        self.TREE_DEPTH = math.ceil(math.log2(queue_size + 1))
        self.NODES_NEEDED = (1 << self.TREE_DEPTH) - 1
        
        # Initialize the queue with zeros
        self.queue = [0] * self.NODES_NEEDED
        self.size = 0
        
        # Node display properties
        self.node_radius = 0.4
        self.node_spacing_h = 1.2  # Increased from 0.7
        self.node_spacing_v = 1.4  # Increased from 1.0
        
        # Store the visualization elements
        self.node_circles = {}
        self.node_values = {}
        self.node_edges = {}
        
        # Operation tracking
        self.current_operation = None
        self.input_data = None
        
        # Create animation directory
        self.animation_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "animation_py/animation")
        os.makedirs(self.animation_dir, exist_ok=True)

    def get_node_position(self, index):
        level = math.floor(math.log2(index + 1))
        nodes_in_level = 2**level
        position_in_level = index - (2**level - 1)
        
        # Calculate x position based on level and position in level
        x = (position_in_level - (nodes_in_level - 1) / 2) * (2**(self.TREE_DEPTH - level - 1)) * self.node_spacing_h
        # Move the tree further down in the frame
        y = (self.TREE_DEPTH - level) * self.node_spacing_v - 3.75  # Increased vertical offset to move tree down
        
        return np.array([x, y, 0])
    
    def create_tree_visualization(self):
        # Create title with more space at the top
        title = Text("RegisterTree Animation", font_size=48).to_edge(UP, buff=1.0)  # Increased top buffer even more
        self.add(title)
        
        # Create status displays
        self.operation_text = Text("", font_size=32).to_edge(DOWN, buff=0.5)
        self.input_display = Text("Input: None", font_size=28).to_corner(DR, buff=0.5)
        self.output_display = Text("Output: None", font_size=28).to_corner(DL, buff=0.5)
        self.add(self.operation_text, self.input_display, self.output_display)
        
        # Create all nodes
        for i in range(min(self.NODES_NEEDED, self.QUEUE_SIZE + 5)):
            pos = self.get_node_position(i)
            
            # Create circle
            circle = Circle(radius=self.node_radius, color=BLUE_E, fill_opacity=0.2)
            circle.move_to(pos)
            self.node_circles[i] = circle
            
            # Create value text
            value_text = Text(str(0), font_size=24)
            value_text.move_to(pos)
            self.node_values[i] = value_text
            
            self.add(circle, value_text)
            
            # Create edges to children
            left_child = 2*i + 1
            right_child = 2*i + 2
            
            if left_child < self.NODES_NEEDED:
                child_pos = self.get_node_position(left_child)
                edge = Line(pos, child_pos, color=GRAY, stroke_opacity=0.5)
                self.node_edges[(i, left_child)] = edge
                self.add(edge)
            
            if right_child < self.NODES_NEEDED:
                child_pos = self.get_node_position(right_child)
                edge = Line(pos, child_pos, color=GRAY, stroke_opacity=0.5)
                self.node_edges[(i, right_child)] = edge
                self.add(edge)
    
    def update_node_visualization(self, animated=True):
        animations = []
        
        # Update node values
        for i in range(self.NODES_NEEDED):
            # Get current value
            value = self.queue[i]
            
            # Update node appearance - just check if value is 0 to determine color
            if value != 0:
                # Active node
                circle_anim = self.node_circles[i].animate.set_fill(color=BLUE, opacity=0.5).set_stroke(color=BLUE)
                value_color = WHITE
            else:
                # Inactive node (zero value)
                circle_anim = self.node_circles[i].animate.set_fill(color=GRAY_E, opacity=0.2).set_stroke(color=GRAY)
                value_color = GRAY
            
            # Update value text
            old_text = self.node_values[i]
            new_text = Text(str(value), font_size=24, color=value_color).move_to(old_text.get_center())
            text_anim = Transform(old_text, new_text)
            
            if animated:
                animations.extend([circle_anim, text_anim])
            else:
                self.node_circles[i].set_fill(color=BLUE if value != 0 else GRAY_E, 
                                          opacity=0.5 if value != 0 else 0.2)
                self.node_circles[i].set_stroke(color=BLUE if value != 0 else GRAY)
                self.remove(self.node_values[i])
                self.node_values[i] = new_text
                self.add(new_text)
        
        # Update status displays
        operation_str = f"{self.current_operation}" if self.current_operation else ""
        input_str = f"Input: {self.input_data}" if self.input_data is not None else "Input: None"
        output_str = f"Output: {self.queue[0]}" if self.size > 0 else "Output: Empty"
        
        new_op_text = Text(operation_str, font_size=32).to_edge(DOWN, buff=0.5)
        new_input_text = Text(input_str, font_size=28).to_corner(DR, buff=0.5)
        new_output_text = Text(output_str, font_size=28).to_corner(DL, buff=0.5)
        
        op_anim = Transform(self.operation_text, new_op_text)
        input_anim = Transform(self.input_display, new_input_text)
        output_anim = Transform(self.output_display, new_output_text)
        
        if animated:
            animations.extend([op_anim, input_anim, output_anim])
            self.play(*animations, run_time=1)
        else:
            self.remove(self.operation_text, self.input_display, self.output_display)
            self.operation_text = new_op_text
            self.input_display = new_input_text
            self.output_display = new_output_text
            self.add(self.operation_text, self.input_display, self.output_display)
    
    def heap_maintenance(self):
        """Perform heap property maintenance - one round only"""
        if self.size <= 1:
            return
        
        # First process even levels
        self.current_operation = "Heap Maintenance (Even Levels)"
        self.update_node_visualization()
        self._process_tree_level("even")
        
        # Then process odd levels
        self.current_operation = "Heap Maintenance (Odd Levels)"
        self.update_node_visualization()
        self._process_tree_level("odd")
    
    def enqueue(self, value):
        """Add a value to the queue"""
        if self.size >= self.QUEUE_SIZE:
            print("Queue is full, can't enqueue")
            return
        
        self.current_operation = "Enqueue Operation"
        self.input_data = value
        
        self.wait(0.5)
        
        # 2. Find the first empty slot (a slot with 0)
        insert_index = None
        for i in range(self.NODES_NEEDED):
            if self.queue[i] == 0:
                insert_index = i
                break
        
        if insert_index is None:
            print("No empty slot found, can't enqueue")
            return

        # 1. Initial state with highlighting the root
        root_highlight = self.node_circles[insert_index].copy().set_fill(RED, opacity=0.5).set_stroke(RED)
        self.play(FadeIn(root_highlight))
        self.wait(0.5)
        self.play(FadeOut(root_highlight))

        # Insert the value
        self.queue[insert_index] = value
        self.size += 1
        
        # Update visualization after insertion
        self.update_node_visualization()
        
        # 3. Heapify - just one round
        self.heap_maintenance()
        
        self.current_operation = None
        self.input_data = None
        self.update_node_visualization()
        self.wait(0.5)
    
    def dequeue(self):
        """Remove the root element"""
        if self.size <= 0:
            print("Queue is empty, can't dequeue")
            return
        
        self.current_operation = "Dequeue Operation"
        
        self.wait(0.5)
        
        # 1. Initial state with highlighting the root
        root_highlight = self.node_circles[0].copy().set_fill(RED, opacity=0.5).set_stroke(RED)
        self.play(FadeIn(root_highlight))
        self.wait(0.5)
        self.play(FadeOut(root_highlight))
        
        # 2. Remove root and shift elements
        dequeued_value = self.queue[0]
        
        # Set root to 0 and reorganize
        self.queue[0] = 0
        self.size -= 1
        
        # Update visualization
        self.update_node_visualization()
        
        # 3. Heapify - just one round
        self.heap_maintenance()
        
        self.current_operation = None
        self.input_data = None
        self.update_node_visualization()
        self.wait(0.5)
    
    def replace(self, value):
        """Replace the root element with a new value"""
        if self.size <= 0:
            # If empty, just enqueue
            self.enqueue(value)
            return
        
        self.current_operation = "Replace Operation"
        self.input_data = value
        
        self.wait(0.5)
        
        # 1. Initial state with highlighting the root
        root_highlight = self.node_circles[0].copy().set_fill(YELLOW, opacity=0.5).set_stroke(YELLOW)
        self.play(FadeIn(root_highlight))
        self.wait(0.5)
        self.play(FadeOut(root_highlight))
        
        # 2. Replace root
        replaced_value = self.queue[0]
        self.queue[0] = value
        
        # Update text with animation
        self.update_node_visualization()

        # 3. Heapify - just one round
        self.heap_maintenance()
        
        self.current_operation = None
        self.input_data = None
        self.update_node_visualization()
        self.wait(0.5)
    
    def _process_tree_level(self, level_type):
        """Process tree nodes at specific level types (even or odd) - all levels at once"""
        # First highlight all nodes at this level type
        level_highlights = []
        level_comparisons = []
        level_nodes = []
        
        # Gather all nodes to process at this level type (all even or odd levels)
        for lvl in range(self.TREE_DEPTH):
            # Skip levels that don't match our target type
            if (lvl % 2 == 0 and level_type != "even") or (lvl % 2 == 1 and level_type != "odd"):
                continue
            
            # Highlight all nodes at this level that have children
            for i in range((1 << lvl) - 1, min((1 << (lvl + 1)) - 1, self.NODES_NEEDED)):
                if 2*i+1 >= self.NODES_NEEDED:
                    continue
                
                # Highlight the parent node
                parent_highlight = self.node_circles[i].copy().set_fill(YELLOW, opacity=0.3).set_stroke(YELLOW)
                level_highlights.append(parent_highlight)
                
                # Store this node for processing
                level_nodes.append(i)
        
        # Highlight all parent nodes at these levels
        if level_highlights:
            self.play(
                *[FadeIn(h) for h in level_highlights],
                run_time=0.7
            )
            self.wait(0.3)
        
        # Now highlight all children of the selected nodes
        for i in level_nodes:
            # Highlight children being compared
            if 2*i+1 < self.NODES_NEEDED:
                left_highlight = self.node_circles[2*i+1].copy().set_fill(GREEN, opacity=0.3).set_stroke(GREEN)
                level_comparisons.append(left_highlight)
            
            if 2*i+2 < self.NODES_NEEDED:
                right_highlight = self.node_circles[2*i+2].copy().set_fill(RED, opacity=0.3).set_stroke(RED)
                level_comparisons.append(right_highlight)
        
        # Show all children comparisons
        if level_comparisons:
            self.play(
                *[FadeIn(h) for h in level_comparisons],
                run_time=0.7
            )
            self.wait(0.3)
        
        # Process all swaps at once for all nodes at these levels
        swaps_performed = {}  # Track which nodes need to be swapped
        
        for i in level_nodes:
            parent = self.queue[i]
            left_child = self.queue[2*i+1] if 2*i+1 < self.NODES_NEEDED else 0
            right_child = self.queue[2*i+2] if 2*i+2 < self.NODES_NEEDED else 0
            
            # Compare logic (max-heap): parent should be larger than both children
            left_greater_than_right = left_child > right_child
            parent_less_than_left = parent < left_child
            parent_less_than_right = parent < right_child
            
            # Determine which nodes need to be swapped
            if left_greater_than_right and parent_less_than_left:
                # Need to swap parent with left child
                swaps_performed[i] = ("left", parent, left_child)
            elif not left_greater_than_right and parent_less_than_right:
                # Need to swap parent with right child
                swaps_performed[i] = ("right", parent, right_child)
        
        # Perform all swaps for all levels simultaneously
        if swaps_performed:
            swap_animations = []
            
            for i, (direction, parent_val, child_val) in swaps_performed.items():
                if direction == "left":
                    # Update the queue values
                    self.queue[i], self.queue[2*i+1] = self.queue[2*i+1], self.queue[i]
                    
                    # Prepare animations
                    parent_text = Text(str(child_val), font_size=24).move_to(self.node_values[i].get_center())
                    child_text = Text(str(parent_val), font_size=24).move_to(self.node_values[2*i+1].get_center())
                    
                    swap_animations.append(Transform(self.node_values[i], parent_text))
                    swap_animations.append(Transform(self.node_values[2*i+1], child_text))
                    
                elif direction == "right":
                    # Update the queue values
                    self.queue[i], self.queue[2*i+2] = self.queue[2*i+2], self.queue[i]
                    
                    # Prepare animations
                    parent_text = Text(str(child_val), font_size=24).move_to(self.node_values[i].get_center())
                    child_text = Text(str(parent_val), font_size=24).move_to(self.node_values[2*i+2].get_center())
                    
                    swap_animations.append(Transform(self.node_values[i], parent_text))
                    swap_animations.append(Transform(self.node_values[2*i+2], child_text))
            
            # Perform all swaps at once
            if swap_animations:
                self.play(*swap_animations, run_time=0.8)
                self.update_node_visualization(animated=False)
        
        # Remove all highlights
        all_highlights = level_highlights + level_comparisons
        if all_highlights:
            self.play(*[FadeOut(h) for h in all_highlights], run_time=0.5)
    
    def construct(self):
        # Initialize the tree visualization
        self.create_tree_visualization()
        
        # Initial state pause
        self.wait(1)
        
        # Start with the tree completely filled
        self.current_operation = "Initializing Tree"
        self.update_node_visualization()
        
        # Initialize the queue with random values to fill the tree completely
        random_values = [49, 44, 46, 41, 38, 30, 28, 9, 5, 33, 35, 16, 12, 18, 27]
        
        # Fill the tree all at once first
        for i, value in enumerate(random_values):
            if i < self.QUEUE_SIZE:
                self.queue[i] = value
                self.size += 1
        
        # Apply heap maintenance to make sure the tree is properly structured
        # self.heap_maintenance()
        
        # Show the initial filled state
        self.current_operation = "Tree Initialized"
        self.update_node_visualization()
        self.wait(2)
        
        # Test Case 1: Dequeue nodes
        self.current_operation = "Test Case 1: Dequeue Test"
        self.update_node_visualization()
        self.wait(2)
        
        # Perform 2 dequeues
        for _ in range(2):
            self.dequeue()
        
        # Test Case 2: Enqueue nodes
        self.current_operation = "Test Case 2: Enqueue Test"
        self.update_node_visualization()
        self.wait(2)
        
        # Enqueue 2 new values
        new_values = [30, 65]
        for value in new_values:
            self.enqueue(value)
        
        # Test Case 3: Replace nodes
        self.current_operation = "Test Case 3: Replace Test"
        self.update_node_visualization()
        self.wait(2)
        
        # Replace 2 values
        replace_values = [95, 72]
        for value in replace_values:
            self.replace(value)
        
        # Test Case 4: Stress Test (simplified)
        self.current_operation = "Test Case 4: Stress Test"
        self.update_node_visualization()
        self.wait(2)
        
        # Mix of operations
        operations = [
            ("enqueue", 45),
            ("dequeue", None),
            ("replace", 67),
            ("enqueue", 39),
            ("dequeue", None),
            ("replace", 91)
        ]
        
        for op, value in operations:
            if op == "enqueue":
                self.enqueue(value)
            elif op == "dequeue":
                self.dequeue()
            elif op == "replace":
                self.replace(value)
        
        # Final state
        self.current_operation = "Animation Complete"
        self.update_node_visualization()
        self.wait(2)


# Function to generate animation
def main():
    # Create output directory
    output_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "animation_py/animation")
    os.makedirs(output_dir, exist_ok=True)
    
    # Set output file path
    output_file = os.path.join(output_dir, "RegisterTreeAnime.mp4")
    
    # Configure Manim for this specific scene
    config.output_file = output_file
    config.media_dir = output_dir
    
    print(f"Generating RegisterTree animation...")
    print(f"Output will be saved to: {output_file}")
    
    # Run Manim to create the animation
    scene = RegisterTreeAnimation(queue_size=15, data_width=16)
    scene.render()
    
    print(f"Animation complete! File saved to {output_file}")

if __name__ == "__main__":
    main()
