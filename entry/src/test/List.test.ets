import localUnitTest from './LocalUnit.test';
import relaySyncTest from './RelaySync.test';

export default function testsuite() {
  localUnitTest();
  relaySyncTest();
}