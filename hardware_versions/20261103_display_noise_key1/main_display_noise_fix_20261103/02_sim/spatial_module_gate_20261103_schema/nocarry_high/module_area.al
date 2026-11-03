<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/spatial_module_gate_20261103_schema/nocarry_high">
    <Project_Created_Time></Project_Created_Time>
    <TD_Encoding>UTF-8</TD_Encoding>
    <TD_Version>6.2.200067</TD_Version>
    <Name>module_area</Name>
    <HardWare>
        <Family>PH1</Family>
        <Device>PH1P35MDG324</Device>
        <Speed>-3</Speed>
    </HardWare>
    <Source_Files><Verilog><File Path="D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/spatial_module_gate_20261103_schema/nocarry_high/module_source.v"><FileInfo>
<Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&R" Val="true"/>
<Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="1"/>
</FileInfo></File><File Path="D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/spatial_module_gate_20261103_schema/nocarry_high/module_area_top.v"><FileInfo>
<Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&R" Val="true"/>
<Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="2"/>
</FileInfo></File></Verilog></Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE><LABEL>module_area_top</LABEL><MODULE>module_area_top</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>
    <Property>
    </Property>
    <Device_Settings>
    </Device_Settings>
    <Configurations>
        <Control0>
            <mclk_freq>33MHz</mclk_freq>
        </Control0>
        <FeatureRow>
            <boot_mode>mspix4</boot_mode>
        </FeatureRow>
    </Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true" useDefaultScript="false">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
                <BitgenProperty::GeneralOption>
                    <compress>on</compress>
                </BitgenProperty::GeneralOption>
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>








