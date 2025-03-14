"""
Unit tests for parsers.py
"""
import unittest
import os
from parsers import parse_achieved_frequencies, parse_metrics, process_directory


class TestParsers(unittest.TestCase):
    def setUp(self):
        # Path to the real Vivado analysis log file
        self.log_file = "/home/charlielinux/Workspace/hwpq_qw2246/bram_tree/vivado_analysis_results_16bit/vivado_analysis_on_queue_size_65535.txt"
        
        # Ensure the file exists
        self.assertTrue(os.path.exists(self.log_file), f"Test file {self.log_file} does not exist")
    
    def test_parse_achieved_frequencies(self):
        """Test parsing of frequencies and achieved frequencies."""
        frequencies, achieved_frequencies = parse_achieved_frequencies(self.log_file)
        
        # Check that the correct values were extracted
        self.assertEqual(len(frequencies), 8)
        self.assertEqual(len(achieved_frequencies), 8)
        
        # Check specific values
        self.assertEqual(frequencies, [100.0, 150.0, 200.0, 250.0, 300.0, 350.0, 400.0, 450.0])
        self.assertEqual(achieved_frequencies, [
            228.311, 235.368, 238.209, 285.307, 297.059, 292.044, 299.401, 305.696
        ])
    
    def test_parse_metrics(self):
        """Test parsing of metrics for the maximum achieved frequency."""
        metrics = parse_metrics(self.log_file)
        
        # Check that we get a dictionary with metrics
        self.assertIsInstance(metrics, dict)
        
        # The max achieved frequency is 305.696 MHz, which occurs at given frequency of 450.0 MHz
        # So we should check for the metrics at that frequency
        self.assertEqual(metrics["queue_size"], 65535)
        self.assertEqual(metrics["max_achieved_frequency"], 305.696)
        self.assertEqual(metrics["power"], 0.548)
        self.assertEqual(metrics["luts_used"], 348)
        self.assertEqual(metrics["luts_util_percent"], 0.25)
        self.assertEqual(metrics["registers_used"], 204)
        self.assertEqual(metrics["registers_util_percent"], 0.07)
        self.assertEqual(metrics["bram_used"], 30.0)
        self.assertEqual(metrics["bram_util_percent"], 10.00)
    
    def test_process_directory(self):
        """Test the process_directory function"""
        data_dict = process_directory(self.test_log_dir)
        
        # Check that data was extracted
        self.assertGreater(len(data_dict), 0, "No data was extracted from the directory")
        
        # Verify the structure of the returned dictionary
        for queue_size, metrics in data_dict.items():
            self.assertIsInstance(queue_size, int, "Queue size should be an integer")
            self.assertIsInstance(metrics, dict, "Metrics should be a dictionary")
            
            # Check that the metrics dictionary contains the expected keys
            self.assertIn("max_achieved_frequency", metrics, "Missing max_achieved_frequency in metrics")
            self.assertGreater(metrics["max_achieved_frequency"], 0, "Max achieved frequency should be positive")
            
            # Check for other expected metrics
            expected_keys = ["luts_used", "luts_util_percent", "registers_used", "registers_util_percent", 
                             "bram_used", "bram_util_percent"]
            
            for key in expected_keys:
                if key in metrics:
                    self.assertIsInstance(metrics[key], (int, float), f"{key} should be a number")
            
            # Verify that queue_size in metrics matches the dictionary key
            if "queue_size" in metrics:
                self.assertEqual(metrics["queue_size"], queue_size, 
                               "Queue size in metrics should match dictionary key")
    
    def test_nonexistent_file(self):
        """Test behavior with a nonexistent file."""
        with self.assertRaises(FileNotFoundError):
            parse_achieved_frequencies("/home/charlielinux/Workspace/hwpq_qw2246/bram_tree/vivado_analysis_results_16bit/vivado_analysis_on_queue_size_65536.txt") # queue size 65536 does not exist


if __name__ == "__main__":
    unittest.main()
