import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { incrementCount } from './incrementCount';
export { resetGlobalCounter } from './resetGlobalCounter';
export { cleanupOldData } from './cleanupOldData';
