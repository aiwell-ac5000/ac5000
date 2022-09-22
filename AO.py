import smbus
import time
import sys
import getopt
 
bus = smbus.SMBus(0)
 
def set_value(DAC_Address,DAC_Chan,DAC_VREF):
        value = int(DAC_VREF)
        k = value >> 8, value & 0xFF
        z = list(k)
        bus.write_i2c_block_data(DAC_Address, DAC_Chan, z)
 
def main(argv):
        DAC_Address=0x60
        DAC_Chan=0x50
        DAC_SHUTDOWN = 0x60 #BIT14 & BIT15
        DAC_GAIN2 = 0x10 #BIT13
        DAC_VREF = 0x80 #BIT15 VREF is 2.048V
 
        try:
                opts, args = getopt.getopt(argv,"h:d:c:v:")
        except getopt.GetoptError:
                print 'test.py -d <device_reg> -c <channel> -v <value>'
                print 'device_reg can be 0x60, 0x61, 0x62, 0x63, 0x64, 0x65 or 0x66'
                print 'channel can be 1,2,3,4'
                print 'value can be 0-4095'
                sys.exit(2)
        for opt, arg in opts:
                if opt == '-h':
                        print 'test.py -d <device_reg> -c <channel> -v <value>'
                        print 'device_reg can be 0x60, 0x61, 0x62, 0x63, 0x64, 0x65 or 0x66'
                        print 'channel can be 1,2,3,4'
                        print 'value can be 0-4095'
                        sys.exit()
                elif opt in ("-d"):
                        DAC_Address = int(arg[2:],16)
                elif opt in ("-c"):
                        if arg == '1':
                                DAC_Chan = 0x50
                        elif arg == '2':
                                DAC_Chan = 0x52
                        elif arg == '3':
                                DAC_Chan = 0x54
                        elif arg == '4':
                                DAC_Chan = 0x56
                        # print DAC_Chan
                elif opt in ("-v"):
                        if arg.startswith("0x"):
                                DAC_VREF = int(arg[2:],16)
                        else:
                                DAC_VREF = arg
                        print DAC_VREF
        set_value(DAC_Address,DAC_Chan,DAC_VREF)
 
if __name__ == "__main__":
   main(sys.argv[1:])
