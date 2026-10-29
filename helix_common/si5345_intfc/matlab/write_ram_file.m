
function write_ram_file(rwdt,ram_init,ninit,nval,opath)

    ttb = {'    '};
    tsp = {' '};
    tcn = {';'};        
    rln = hex2dec('7F');
    ram_dwdt = num2str(rwdt+rwdt/8);%data width
    ram_awdt = num2str(10);%10 for 16 or 32-bit data, despite UG
    ram_ewdt = num2str(rwdt/8);%WE width
    ram_dfltd = strcat(ram_dwdt,'UX"0",');
    ram_dflta = strcat(ram_awdt,'UX"0",');
    ram_dflte = strcat(ram_ewdt,'UX"3",');
    ramd_rngl = num2str(rwdt-1);
    rama_rngl = num2str(10-1);
    rama_vec = strcat('STD_LOGIC_VECTOR(TO_UNSIGNED(cfg_adr,',ram_awdt,'));');
    ramd_sig = strcat(': std_logic_vector(',ram_dwdt,'-1 downto 0);');
    rama_sig = strcat(': std_logic_vector(',ram_awdt,'-1 downto 0);');
    ramd_prti = strcat(': in std_logic_vector(',ramd_rngl,' downto 0);');
    rama_prti = strcat(': in std_logic_vector(',rama_rngl,' downto 0);');
    ramd_prto = strcat(': out std_logic_vector(',ramd_rngl,' downto 0);');
    ramd_prtoe = strcat(': out std_logic_vector(',ramd_rngl,' downto 0)');
    
    %write the HDL file
    %########################################
    fid = fopen(strcat(opath,'si5345_cfg_ram.vhd'),'wt');
    fprintf(fid,'%s\n','library ieee;');
    fprintf(fid,'%s%s\n',string(ttb),'use ieee.std_logic_1164.all;');
    fprintf(fid,'%s%s\n',string(ttb),'use ieee.numeric_std.all;');
    fprintf(fid,'%s\n','library unisim;');
    fprintf(fid,'%s%s\n',string(ttb),'use unisim.vcomponents.all;');
    fprintf(fid,'%s\n','library unimacro;');
    fprintf(fid,'%s%s\n',string(ttb),'use unimacro.vcomponents.all;');
    fprintf(fid,'\n\n');
    %entity stuff
    fprintf(fid,'%s\n','entity si5345_cfg_ram is');
    fprintf(fid,'%s\n','port(');
    fprintf(fid,'%s%s%s%s\n',string(ttb),'clk    ',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in std_logic;');
    fprintf(fid,'%s%s%s%s\n',string(ttb),'ce     ',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in std_logic;');
    fprintf(fid,'%s%s%s%s\n',string(ttb),'reset  ',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in std_logic;');
    fprintf(fid,'%s%s%s%s\n',string(ttb),'wren   ',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in std_logic;');
    fprintf(fid,'%s%s%s%s\n',string(ttb),'wr_adr ',string(strcat(ttb,ttb,ttb,ttb,ttb)),rama_prti);
    fprintf(fid,'%s%s%s%s\n',string(ttb),'wr_data',string(strcat(ttb,ttb,ttb,ttb,ttb)),ramd_prti);
    fprintf(fid,'%s%s%s%s%s%s%s\n',string(ttb),'cfg_adr',string(strcat(ttb,ttb,ttb,ttb,ttb)),': in integer range 0 to',string(tsp),num2str(nval-1),';');
    fprintf(fid,'%s%s%s%s%s\n',string(ttb),'cfg_out',string(strcat(ttb,ttb,ttb,ttb,ttb)),ramd_prtoe,');');
    fprintf(fid,'%s\n','end entity;');
    fprintf(fid,'\n\n');
    
    %RAM Arch
    %########################################
    fprintf(fid,'%s\n','architecture cfg_ram_arch of si5345_cfg_ram is');
    fprintf(fid,'\n');        
    fprintf(fid,'%s%s\n',string(strcat(ttb,'signal cfg_adr_vec',ttb,ttb,ttb)),rama_sig);
    fprintf(fid,'%s%s\n',string(strcat(ttb,'signal cfg_in_vec',ttb,ttb,ttb)),ramd_sig);
    fprintf(fid,'%s%s\n',string(strcat(ttb,'signal cfg_out_vec',ttb,ttb,ttb)),ramd_sig);
    fprintf(fid,'%s%s\n',string(strcat(ttb,'signal len_out_vec',ttb,ttb,ttb)),ramd_sig);
    fprintf(fid,'\n');
    fprintf(fid,'%s\n','begin');
    fprintf(fid,'\n');
    %control value ram
    fprintf(fid,'%s%s\n',string(ttb),'ctrl_ram_ins : BRAM_SDP_MACRO');
    fprintf(fid,'%s%s\n',string(ttb),'generic map (');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'BRAM_SIZE            => "36Kb",');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'DEVICE               => "7SERIES",');
    fprintf(fid,'%s%s%s\n',string(strcat(ttb,ttb)),string(strcat('WRITE_WIDTH          =>',tsp)),strcat(ram_dwdt,','));
    fprintf(fid,'%s%s%s\n',string(strcat(ttb,ttb)),string(strcat('READ_WIDTH           =>',tsp)),strcat(ram_dwdt,','));
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'DO_REG               => 0,');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'INIT_FILE            => "NONE",');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'SIM_COLLISION_CHECK  => "ALL",');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'SRVAL                => X"000000000000000000",');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'WRITE_MODE           => "WRITE_FIRST",');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'INIT                 => X"000000000000000000",');
    %our init params
    for i = 1:1:rln
        if i > ninit
            fprintf(fid,'%s%s%s\n',string(strcat(ttb,ttb)),strcat('INIT_',(dec2hex(i-1,2))),' => X"0000000000000000000000000000000000000000000000000000000000000000",');
        else
            fprintf(fid,'%s%s%s%s\n',string(strcat(ttb,ttb)),string(strcat('INIT_',dec2hex(i-1,2),tsp,'=>',tsp)),ram_init(1,i),',');
        end;
    end;
    for i = 1:1:16
        if i < 16
            fprintf(fid,'%s%s%s\n',string(strcat(ttb,ttb)),strcat('INITP_',(dec2hex(i-1,2))),' => X"0000000000000000000000000000000000000000000000000000000000000000",');
        else
            fprintf(fid,'%s%s%s\n',string(strcat(ttb,ttb)),strcat('INITP_',(dec2hex(i-1,2))),' => X"0000000000000000000000000000000000000000000000000000000000000000")');
        end;
    end;
    fprintf(fid,'%s%s\n',string(ttb),'port map(');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'DO                   => cfg_out_vec,');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'DI                   => cfg_in_vec,');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'RDADDR               => cfg_adr_vec,');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'RDCLK                => clk,');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'RDEN                 => ''1'',');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'REGCE                => ''1'',');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'RST                  => reset,');
    fprintf(fid,'%s%s%s\n',string(strcat(ttb,ttb)),'WE                   => ',ram_dflte);
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'WRADDR               => wr_adr,');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'WRCLK                => clk,');
    fprintf(fid,'%s%s\n',string(strcat(ttb,ttb)),'WREN                 => wren');
    fprintf(fid,'%s%s\n',string(ttb),');');
    fprintf(fid,'\n');    
    
    fprintf(fid,'\n');    
    fprintf(fid,'%s\n',string(strcat(ttb,'cfg_adr_vec <=',tsp,rama_vec)));
    fprintf(fid,'%s\n',string(strcat(ttb,'out_gen : for I in 1 to',tsp,ram_ewdt,tsp,'generate')));
    fprintf(fid,'%s\n',string(strcat(ttb,ttb,'cfg_out((I*8)-1 downto (I*8)-8) <= cfg_out_vec((I*8)+(I-2) downto (I-1)*8+(I-1));')));
    fprintf(fid,'%s\n',string(strcat(ttb,ttb,'cfg_in_vec((I*8)+(I-1) downto (I-1)*8+(I-1)) <= ''0'' & wr_data((I*8)-1 downto (I*8)-8);')));
    fprintf(fid,'%s\n',string(strcat(ttb,'end generate;')));    
    fprintf(fid,'\n');
    %end the arch
    fprintf(fid,'%s\n','end cfg_ram_arch;');
    fprintf(fid,'%s\n');
    fclose(fid);

end