import unittest
import os
import sys
import numpy as np
from math import log2

# Import the modules to test
import data_processor
from config import TOTAL_LUTS, PERFORMANCE_FACTORS

class TestDataProcessor(unittest.TestCase):
    
    def setUp(self):
        """Set up test fixtures"""
        # Path to the directory with log files for testing
        self.test_log_dir = os.path.join(os.path.dirname(__file__), 'bram_tree/vivado_analysis_results_16bit')
        
        # Ensure the test directory exists
        self.assertTrue(os.path.exists(self.test_log_dir), 
                       f"Test directory {self.test_log_dir} does not exist")
        
        # Ensure there's at least one log file in the directory
        log_files = [f for f in os.listdir(self.test_log_dir) 
                    if f.endswith('.txt') and 'vivado_analysis_on_queue_size' in f]
        self.assertTrue(len(log_files) > 0, 
                       f"No log files found in {self.test_log_dir}")
        
        # Store sample log file path for individual file tests
        self.sample_log_file = os.path.join(self.test_log_dir, log_files[0])


if __name__ == '__main__':
    unittest.main()
