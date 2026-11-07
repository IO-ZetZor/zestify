import QtQuick
import QtTest
import "../../shell/lib/proc.js" as Proc

TestCase {
    name: "Proc"

    function test_parses_meminfo() {
        const info = Proc.parseMeminfo("MemTotal: 16000000 kB\nMemAvailable: 8000000 kB\n");
        compare(info.memTotal, 16000000 * 1024);
        compare(info.memAvailable, 8000000 * 1024);
        compare(info.used, 8000000 * 1024);
    }

    function test_parses_cpu_sample() {
        const sample = Proc.parseCpu("cpu  100 0 50 800 20 0 5 0 0 0\ncpu0 50 0 25 400 10 0 2 0 0 0\n");
        compare(sample.total, 975);
        compare(sample.idle, 820);
    }

    function test_parses_netdev_without_loopback() {
        const net = Proc.parseNetdev("Inter-|Receive |Transmit\n face |bytes packets|bytes packets\n    lo: 1 2 0 0 0 0 0 0 3 4 0 0 0 0 0 0\n  eth0: 100 2 0 0 0 0 0 0 50 4 0 0 0 0 0 0\n");
        compare(net.rx, 100);
        compare(net.tx, 50);
    }

    function test_computes_network_throughput() {
        const previous = { rx: 1000, tx: 500 };
        const current = { rx: 3000, tx: 1500 };
        compare(Proc.netRate(previous, current, 2), 1500);
        compare(Proc.netRate(null, current, 2), 0);
        compare(Proc.netRate(previous, current, 0), 0);
    }
}
