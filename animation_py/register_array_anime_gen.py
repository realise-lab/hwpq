from manim import *
import math
import numpy as np
import os

# Configure Manim
config.pixel_height = 1080
config.pixel_width = 1920
config.frame_rate = 30

class RegisterArrayAnimation(Scene):
    def __init__(self, queue_size=16, data_width=16, **kwargs):
        super().__init__(**kwargs)
        self.QUEUE_SIZE = queue_size
        self.DATA_WIDTH = data_width
        self.PAIR_COUNT = queue_size // 2
        
        # Initialize the queue with zeros
        self.queue = [0] * self.QUEUE_SIZE
        self.size = 0
        
        # Node display properties - slightly larger for 8-element array
        self.node_radius = 0.35
        self.node_spacing_h = 1.1
        self.node_spacing_v = 1.3
        
        # Store the visualization elements
        self.node_circles = {}
        self.node_values = {}
        self.node_edges = {}
        self.stage1_nodes = {}
        self.stage2_nodes = {}
        self.max_min_nodes = {}
        
        # Operation tracking
        self.current_operation = None
        self.input_data = None
        
        # Create animation directory
        self.animation_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "animation_py/animation")
        os.makedirs(self.animation_dir, exist_ok=True)

    def get_node_position(self, index, stage=0):
        # For the main array (stage 0), arrange horizontally
        if stage == 0:
            x = (index - (self.QUEUE_SIZE - 1) / 2) * self.node_spacing_h
            y = 2.5  # Top of the screen
            return np.array([x, y, 0])
        # For stage 1 (after initial operation)
        elif stage == 1:
            x = (index - (self.QUEUE_SIZE - 1) / 2) * self.node_spacing_h
            y = 1.0
            return np.array([x, y, 0])
        # For max-min pairs
        elif stage == 2:
            pair_index = index // 2
            is_max = index % 2 == 0
            x = (pair_index - (self.PAIR_COUNT - 1) / 2) * self.node_spacing_h * 2
            y = 0  
            return np.array([x, y - (0.7 if is_max else 0), 0])
        # For stage 2 (final sorted array)
        elif stage == 3:
            x = (index - (self.QUEUE_SIZE - 1) / 2) * self.node_spacing_h
            y = -2.0
            return np.array([x, y, 0])
    
    def create_array_visualization(self):
        # Create title
        title = Text("Register Array", font_size=48).to_edge(UP, buff=0.5)
        self.add(title)
        
        # Create status displays
        self.operation_text = Text("", font_size=32).to_edge(DOWN, buff=0.5)
        self.input_display = Text("Input: None", font_size=28).to_corner(DR, buff=0.5)
        self.output_display = Text("Output: None", font_size=28).to_corner(DL, buff=0.5)
        self.add(self.operation_text, self.input_display, self.output_display)
        
        # Create stage labels
        stage0_label = Text("Main Array", font_size=24).next_to(self.get_node_position(0, 0), UP, buff=0.5)
        stage1_label = Text("Stage 1", font_size=24).next_to(self.get_node_position(0, 1), UP, buff=0.5)
        stage2_label = Text("Max-Min Pairs", font_size=24).next_to(self.get_node_position(0, 2), LEFT, buff=1.0)
        stage3_label = Text("Sorted Array", font_size=24).next_to(self.get_node_position(0, 3), UP, buff=0.5)
        self.add(stage0_label, stage1_label, stage2_label, stage3_label)
        
        # Create all nodes for the main array
        for i in range(self.QUEUE_SIZE):
            pos = self.get_node_position(i, 0)
            
            # Create circle
            circle = Circle(radius=self.node_radius, color=BLUE_E, fill_opacity=0.2)
            circle.move_to(pos)
            self.node_circles[i] = circle
            
            # Create value text
            value_text = Text(str(0), font_size=20)
            value_text.move_to(pos)
            self.node_values[i] = value_text
            
            self.add(circle, value_text)
            
        # Create stage 1 nodes
        for i in range(self.QUEUE_SIZE):
            pos = self.get_node_position(i, 1)
            circle = Circle(radius=self.node_radius, color=GRAY_E, fill_opacity=0.1)
            circle.move_to(pos)
            
            value_text = Text(str(0), font_size=20, color=GRAY)
            value_text.move_to(pos)
            
            self.stage1_nodes[i] = {"circle": circle, "text": value_text}
            self.add(circle, value_text)
        
        # Create max-min pair nodes
        for i in range(self.QUEUE_SIZE):
            pos = self.get_node_position(i, 2)
            circle = Circle(radius=self.node_radius, color=GRAY_E, fill_opacity=0.1)
            circle.move_to(pos)
            
            value_text = Text(str(0), font_size=20, color=GRAY)
            value_text.move_to(pos)
            
            self.max_min_nodes[i] = {"circle": circle, "text": value_text}
            self.add(circle, value_text)
        
        # Create stage 2 nodes (final sorted array)
        for i in range(self.QUEUE_SIZE):
            pos = self.get_node_position(i, 3)
            circle = Circle(radius=self.node_radius, color=GRAY_E, fill_opacity=0.1)
            circle.move_to(pos)
            
            value_text = Text(str(0), font_size=20, color=GRAY)
            value_text.move_to(pos)
            
            self.stage2_nodes[i] = {"circle": circle, "text": value_text}
            self.add(circle, value_text)
    
    def update_node_visualization(self, animated=True):
        animations = []
        
        # Update main array node values
        for i in range(self.QUEUE_SIZE):
            # Get current value
            value = self.queue[i]
            
            # Update node appearance
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
            new_text = Text(str(value), font_size=20, color=value_color).move_to(old_text.get_center())
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
    
    def animate_pairwise_sorting(self, stage1_values):
        # Clear previous visual states
        self.clear_intermediate_stages()
        
        # Update stage 1 nodes to show the initial operation result
        for i in range(self.QUEUE_SIZE):
            value = stage1_values[i]
            pos = self.get_node_position(i, 1)
            
            if value != 0:
                # Active node
                self.stage1_nodes[i]["circle"].set_fill(color=GREEN, opacity=0.4).set_stroke(color=GREEN)
                color = WHITE
            else:
                # Inactive node
                self.stage1_nodes[i]["circle"].set_fill(color=GRAY_E, opacity=0.2).set_stroke(color=GRAY)
                color = GRAY
            
            # Update text
            self.remove(self.stage1_nodes[i]["text"])
            new_text = Text(str(value), font_size=20, color=color).move_to(pos)
            self.stage1_nodes[i]["text"] = new_text
            self.add(new_text)
        
        self.wait(0.5)
        
        # Calculate max and min pairs
        max_values = []
        min_values = []
        
        for i in range(self.PAIR_COUNT):
            if stage1_values[2*i] > stage1_values[2*i+1]:
                max_values.append(stage1_values[2*i])
                min_values.append(stage1_values[2*i+1])
            else:
                max_values.append(stage1_values[2*i+1])
                min_values.append(stage1_values[2*i])
        
        # Show max-min calculation
        max_arrows = []
        min_arrows = []
        
        for i in range(self.PAIR_COUNT):
            # Calculate positions for source nodes and target nodes
            source1_pos = self.get_node_position(2*i, 1)
            source2_pos = self.get_node_position(2*i+1, 1)
            max_pos = self.get_node_position(2*i, 2)
            min_pos = self.get_node_position(2*i+1, 2)
            
            # Create arrows
            if stage1_values[2*i] > stage1_values[2*i+1]:
                max_arrow = Arrow(start=source1_pos, end=max_pos, color=RED)
                min_arrow = Arrow(start=source2_pos, end=min_pos, color=BLUE)
            else:
                max_arrow = Arrow(start=source2_pos, end=max_pos, color=RED)
                min_arrow = Arrow(start=source1_pos, end=min_pos, color=BLUE)
            
            max_arrows.append(max_arrow)
            min_arrows.append(min_arrow)
        
        # Play the comparison animation
        self.play(*[Create(arrow) for arrow in max_arrows], run_time=0.8)
        self.play(*[Create(arrow) for arrow in min_arrows], run_time=0.8)
        
        # Update the max-min pair nodes
        for i in range(self.PAIR_COUNT):
            max_value = max_values[i]
            min_value = min_values[i]
            
            # Update max node
            max_pos = self.get_node_position(2*i, 2)
            self.max_min_nodes[2*i]["circle"].set_fill(color=RED, opacity=0.4).set_stroke(color=RED)
            self.remove(self.max_min_nodes[2*i]["text"])
            new_max_text = Text(str(max_value), font_size=20, color=WHITE).move_to(max_pos)
            self.max_min_nodes[2*i]["text"] = new_max_text
            self.add(new_max_text)
            
            # Update min node
            min_pos = self.get_node_position(2*i+1, 2)
            self.max_min_nodes[2*i+1]["circle"].set_fill(color=BLUE, opacity=0.4).set_stroke(color=BLUE)
            self.remove(self.max_min_nodes[2*i+1]["text"])
            new_min_text = Text(str(min_value), font_size=20, color=WHITE).move_to(min_pos)
            self.max_min_nodes[2*i+1]["text"] = new_min_text
            self.add(new_min_text)
        
        self.wait(0.5)
        
        # Combine adjacent pairs
        combine_arrows = []
        
        # Create the sorted final array values
        sorted_values = [0] * self.QUEUE_SIZE
        sorted_values[0] = max_values[0]  # Largest element goes to the front
        
        for i in range(self.PAIR_COUNT - 1):
            # Calculate positions
            source1_pos = self.get_node_position(2*i+1, 2)  # min[i]
            source2_pos = self.get_node_position(2*(i+1), 2)  # max[i+1]
            target1_pos = self.get_node_position(2*i+1, 3)
            target2_pos = self.get_node_position(2*i+2, 3)
            
            # Determine sorting for adjacent pairs
            if min_values[i] > max_values[i+1]:
                sorted_values[2*i+1] = min_values[i]
                sorted_values[2*i+2] = max_values[i+1]
                
                arrow1 = Arrow(start=source1_pos, end=target1_pos, color=YELLOW)
                arrow2 = Arrow(start=source2_pos, end=target2_pos, color=YELLOW)
            else:
                sorted_values[2*i+1] = max_values[i+1]
                sorted_values[2*i+2] = min_values[i]
                
                arrow1 = Arrow(start=source2_pos, end=target1_pos, color=YELLOW)
                arrow2 = Arrow(start=source1_pos, end=target2_pos, color=YELLOW)
            
            combine_arrows.extend([arrow1, arrow2])
        
        # Add the last min element
        sorted_values[self.QUEUE_SIZE-1] = min_values[self.PAIR_COUNT-1]
        
        # Play the combine animation
        self.play(*[Create(arrow) for arrow in combine_arrows], run_time=0.8)
        
        # Update the stage 2 nodes (final sorted array)
        for i in range(self.QUEUE_SIZE):
            value = sorted_values[i]
            pos = self.get_node_position(i, 3)
            
            if value != 0:
                # Active node
                self.stage2_nodes[i]["circle"].set_fill(color=PURPLE, opacity=0.4).set_stroke(color=PURPLE)
                color = WHITE
            else:
                # Inactive node
                self.stage2_nodes[i]["circle"].set_fill(color=GRAY_E, opacity=0.2).set_stroke(color=GRAY)
                color = GRAY
            
            # Update text
            self.remove(self.stage2_nodes[i]["text"])
            new_text = Text(str(value), font_size=20, color=color).move_to(pos)
            self.stage2_nodes[i]["text"] = new_text
            self.add(new_text)
        
        self.wait(0.5)
        
        # Clean up arrows
        self.play(
            *[FadeOut(arrow) for arrow in max_arrows + min_arrows + combine_arrows],
            run_time=0.5
        )
        
        # Update the main array with the sorted values
        self.queue = sorted_values.copy()
        self.update_node_visualization()
    
    def clear_intermediate_stages(self):
        # Reset stage 1 nodes
        for i in range(self.QUEUE_SIZE):
            self.stage1_nodes[i]["circle"].set_fill(color=GRAY_E, opacity=0.1).set_stroke(color=GRAY)
            pos = self.get_node_position(i, 1)
            self.remove(self.stage1_nodes[i]["text"])
            new_text = Text("0", font_size=20, color=GRAY).move_to(pos)
            self.stage1_nodes[i]["text"] = new_text
            self.add(new_text)
        
        # Reset max-min pair nodes
        for i in range(self.QUEUE_SIZE):
            self.max_min_nodes[i]["circle"].set_fill(color=GRAY_E, opacity=0.1).set_stroke(color=GRAY)
            pos = self.get_node_position(i, 2)
            self.remove(self.max_min_nodes[i]["text"])
            new_text = Text("0", font_size=20, color=GRAY).move_to(pos)
            self.max_min_nodes[i]["text"] = new_text
            self.add(new_text)
        
        # Reset stage 2 nodes
        for i in range(self.QUEUE_SIZE):
            self.stage2_nodes[i]["circle"].set_fill(color=GRAY_E, opacity=0.1).set_stroke(color=GRAY)
            pos = self.get_node_position(i, 3)
            self.remove(self.stage2_nodes[i]["text"])
            new_text = Text("0", font_size=20, color=GRAY).move_to(pos)
            self.stage2_nodes[i]["text"] = new_text
            self.add(new_text)
    
    def enqueue(self, value):
        """Add a value to the queue"""
        if self.size >= self.QUEUE_SIZE:
            print("Queue is full, can't enqueue")
            return
        
        self.current_operation = "Enqueue Operation"
        self.input_data = value
        
        self.wait(0.5)
        
        # First step: Highlight current queue and show new element
        root_highlight = self.node_circles[0].copy().set_fill(RED, opacity=0.5).set_stroke(RED)
        self.play(FadeIn(root_highlight))
        self.wait(0.5)
        self.play(FadeOut(root_highlight))
        
        # Create stage 1 values: shift elements and add new element
        stage1_values = self.queue.copy()
        for i in range(self.QUEUE_SIZE - 1, 0, -1):
            stage1_values[i] = stage1_values[i-1]
        stage1_values[0] = value
        
        # Update size
        self.size += 1
        
        # Animate pairwise sorting process
        self.animate_pairwise_sorting(stage1_values)
        
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
        
        # First step: Highlight the root element to remove
        root_highlight = self.node_circles[0].copy().set_fill(RED, opacity=0.5).set_stroke(RED)
        self.play(FadeIn(root_highlight))
        self.wait(0.5)
        self.play(FadeOut(root_highlight))
        
        # Create stage 1 values: set root to zero
        stage1_values = self.queue.copy()
        stage1_values[0] = 0
        
        # Update size
        self.size -= 1
        
        # Animate pairwise sorting process
        self.animate_pairwise_sorting(stage1_values)
        
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
        
        # First step: Highlight the root element to replace
        root_highlight = self.node_circles[0].copy().set_fill(YELLOW, opacity=0.5).set_stroke(YELLOW)
        self.play(FadeIn(root_highlight))
        self.wait(0.5)
        self.play(FadeOut(root_highlight))
        
        # Create stage 1 values: set root to new value
        stage1_values = self.queue.copy()
        stage1_values[0] = value
        
        # Animate pairwise sorting process
        self.animate_pairwise_sorting(stage1_values)
        
        self.current_operation = None
        self.input_data = None
        self.update_node_visualization()
        self.wait(0.5)
    
    def construct(self):
        # Initialize the visualization
        self.create_array_visualization()
        
        # Initial state pause
        self.wait(1)
        
        self.current_operation = "Initializing Array"
        self.update_node_visualization()
        self.wait(1)
        
        # Initialize with some values for 8-element array
        random_values = [49, 44, 46, 41, 38, 30, 28, 9]
        
        # Fill the array one by one with enqueue operations
        for i, value in enumerate(random_values):
            if i < self.QUEUE_SIZE:
                self.enqueue(value)
                self.wait(0.5)
        
        # Show the initial state
        self.current_operation = "Array Initialized"
        self.update_node_visualization()
        self.wait(1)
        
        # Test Case 1: Dequeue node
        self.current_operation = "Dequeue"
        self.update_node_visualization()
        self.wait(1)
        
        self.dequeue()
        
        # Test Case 2: Enqueue node
        self.current_operation = "Enqueue"
        self.update_node_visualization()
        self.wait(1)
        
        self.enqueue(30)
        
        # Test Case 3: Replace node
        self.current_operation = "Replace"
        self.update_node_visualization()
        self.wait(1)
        
        self.replace(72)
        
        # Final state
        self.current_operation = "Animation Complete"
        self.update_node_visualization()
        self.wait(1)


# Function to generate animation
def main():
    # Create output directory
    output_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "animation_py/animation")
    os.makedirs(output_dir, exist_ok=True)
    
    # Set output file path
    output_file = os.path.join(output_dir, "register_array_animation.mp4")
    
    # Configure Manim for this specific scene
    config.output_file = output_file
    config.media_dir = output_dir
    
    print(f"Generating RegisterArray animation...")
    print(f"Output will be saved to: {output_file}")
    
    # Run Manim to create the animation
    scene = RegisterArrayAnimation(queue_size=8, data_width=16)
    scene.render()
    
    print(f"Animation complete! File saved to {output_file}")

if __name__ == "__main__":
    main()