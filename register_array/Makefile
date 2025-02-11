include Preferences

####  Case 1: Synthesis Verilog Code in VS Code.  ############# 
# Verilog source files
SRC_FILES :=  $(filter-out %_tb.sv, $(wildcard *.sv)) 
TB_FILES := $(filter %_tb.sv, $(wildcard *.sv)) 

# Output products
SIM_BIN = sim 
SIM_VCD := $(basename $(SRC_FILES)).vcd

# Default target
onlySimulation: $(SIM_BIN) 

# Simulation target
$(SIM_BIN): $(SRC_FILES) $(TB_FILES)
	iverilog -o $(SIM_BIN) $(SRC_FILES) $(TB_FILES)
	vvp $(SIM_BIN) 
ifeq ($(USE_GTKWAVE),YES)
	gtkwave $(SIM_VCD) &
	$(info gtkwave is Chosen for waveform viewing...)
	$(info To Use the default waveform viewing(WaveTrace) set USE_GTKWAVE = NO in the "Preferences" file!)
	$(info Get More Help From The Link Below)
	$(info >> {No Help Info Now!})
	$(info )
else
	$(info Using WaveTrace for waveform viewing...)
	$(info 1  Click ($(basename $(SRC_FILES)).vcd) file.)
	$(info 2  Select all signals: ctrl + A (cmd + A on mac))
	$(info 3  Press enter to view waveform.) 
	$(info )
	$(info However, to use gtkwave, set USE_GTKWAVE = YES in the "Preferences" file!)
	$(info Get More Help From The Link Below)
	$(info >> {No Help Info Now!})
	$(info )
endif 


####  Case 2: Automate Vivado Tasks from VS Code. ############# 
startVivado:
	@echo "Starting Vivado..."
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -mode gui &

openProject:
	@echo "Opening Project: $(wildcard *.xpr)"
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -mode gui $(wildcard *.xpr) &

openBlockDesign:
	@echo "Opening Block Design For: $(wildcard *.xpr)"
	rm -f TCLcommand.tcl $(wildcard *.out)
	@echo 'open_project $(wildcard *.xpr)' > TCLcommand.tcl 
	@echo 'open_bd_design {$(basename $(wildcard *.xpr)).srcs/sources_1/bd/system/system.bd}' >> TCLcommand.tcl 
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -notrace -mode tcl -source TCLcommand.tcl &

wrapper:
	rm -f TCLcommand.tcl $(wildcard *.out)
	@echo 'open_project $(wildcard *.xpr)' > TCLcommand.tcl
	@echo 'open_bd_design {$(basename $(wildcard *.xpr)).srcs/sources_1/bd/system/system.bd}' >> TCLcommand.tcl
	@echo 'make_wrapper -files [get_files ./$(basename $(wildcard *.xpr)).srcs/sources_1/bd/system/system.bd] -top' >> TCLcommand.tcl
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -notrace -mode tcl -source TCLcommand.tcl &

runSimulation:
	rm -f $(wildcard *.out)
	@echo 'open_project $(wildcard *.xpr)' > TCLcommand.tcl
	@echo 'launch_simulation' >> TCLcommand.tcl
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -notrace -mode tcl -source TCLcommand.tcl &

runimplementation:
	rm -f $(wildcard *.out)
	@echo 'open_project $(wildcard *.xpr)' > TCLcommand.tcl
	@echo 'launch_runs synth_1 -jobs 2' >> TCLcommand.tcl
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -notrace -mode tcl -source TCLcommand.tcl &

generateBitstream:	
	rm -f $(wildcard *.out)
	@echo 'open_project $(wildcard *.xpr)' > TCLcommand.tcl
	@echo 'launch_runs synth_design impl_1 -to_step write_bitstream -jobs 2' >> TCLcommand.tcl
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -notrace -mode tcl -source TCLcommand.tcl &

writeTcl:
	rm -f $(wildcard *.out)
	@echo 'open_project $(wildcard *.xpr)' > TCLcommand.tcl
	@echo 'write_project_tcl { $(basename $(wildcard *.xpr)).tcl}' >> TCLcommand.tcl 
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -notrace -mode tcl -source TCLcommand.tcl &

openTcl:
	@ if [ "$(suffix $(wildcard *.tcl))" = ".tcl" ]; then \
		echo "Regenerating Project from TCL file: $(wildcard *.tcl)"; \
		nohup $(VIVADO_PATH)/vivado -nojournal -nolog -mode tcl -source $(wildcard *.tcl); \
	else \
		echMako "No TCL file in current folder: $(CURDIR)"; \
	fi
 
archive:
	rm -rf $(wildcard *.out) ./.Xil/AChiveTempdir
	@echo 'open_project $(wildcard *.xpr)' > TCLcommand.tcl
	@echo "archive_project $(basename $(wildcard *.xpr)).zip -temp_dir ./.Xil/AChiveTempdir -force -include_local_ip_cache -include_config_settings" >> TCLcommand.tcl
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -notrace -mode tcl -source TCLcommand.tcl &

createProject:
	@read -p "Enter the name of the project file: " get_obj; \
	Project_Name=$$get_obj ; \
	echo "	1: $(word 1, $(PYNQZ2_PART))"; \
	echo "	2: $(word 2, $(PYNQZ2_PART))"; \
	echo "	3: $(word 3, $(PYNQZ2_PART))"; \
	echo "	4: Start Vivado gui"; \
	read -p "Choose part: " get_obj; \
	Part_Type=$$get_obj ; \
	case $$Part_Type in \
		1) echo "create_project $$Project_Name $$Project_Name -part $(word 1, $(PYNQZ2_PART))" > TCLcommand.tcl;; \
		2) echo "create_project $$Project_Name $$Project_Name -part $(word 2, $(PYNQZ2_PART))" > TCLcommand.tcl;; \
		3) echo "create_project $$Project_Name $$Project_Name -part $(word 3, $(PYNQZ2_PART))" > TCLcommand.tcl;; \
		4) echo "start_gui"> TCLcommand.tcl;; \
		*) echo "Invalid part choice";; \
	esac
	nohup $(VIVADO_PATH)/vivado -nojournal -nolog -mode tcl -source TCLcommand.tcl & 
getHelp: 
	$(info )
	$(info Check updates for this file here>> {no link for updates yet})
	$(info ------------Available commands are--------)
	$(info ####  Case 1: Simulation Verilog Code in VS Code: Without Vivado.  #############)
	$(info make onlySimulation)
	$(info ####  Case 2: Automate Vivado Tasks from VS Code: With Vivado(in background/forground). #############)
	$(info make getHelp)
	$(info make startVivado)
	$(info make createProject)
	$(info make Wrapper)
	$(info make runSimulation)
	$(info make runSynthesis)
	$(info make runimplementation)
	$(info make generateBitstream)
	$(info make saveAs)
	$(info make writeTcl)
	$(info make archive)
	$(info )

saveAs:
	rm -f $(wildcard *.out)
	@read -p "Enter the name of the project file: " get_obj; \
	echo "Saving project as $(abspath $(dir $(CURDIR))/./$$get_obj)"; \
	echo 'open_project $(wildcard *.xpr)' > TCLcommand.tcl;\
    echo "save_project_as $$get_obj $(abspath $(dir $(CURDIR))/./$$get_obj) -exclude_run_results -force" >> TCLcommand.tcl; \
    nohup $(VIVADO_PATH)/vivado -nojournal -nolog -notrace -mode tcl -source TCLcommand.tcl &

clean:
	rm -f $(wildcard *.out) $(SIM_BIN) $(SIM_VCD)
